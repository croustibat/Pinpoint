import AppKit
import Foundation

/// Everything an undoable editor action can change, captured as one value.
///
/// Snapshots rather than inverse commands: the editor's state is a handful of
/// small arrays plus the base image, so copying it is cheap, and a snapshot
/// can't drift out of sync with the mutation it is supposed to undo the way a
/// hand-written inverse can (`removePin` renumbers the survivors, `applyCrop`
/// remaps every coordinate and replaces the image — both are awkward to invert,
/// trivial to snapshot).
struct EditorSnapshot {
    /// The base image. A crop installs a brand new `NSImage`, so restoring the
    /// previous one is what makes a crop undoable.
    var image: NSImage
    var pins: [Pin]
    var shapes: [Markup]
    var context: String
    /// Selections ride along so that undoing a deletion re-selects what came
    /// back, and undoing a placement restores whatever was selected before.
    var selectedPinID: Pin.ID?
    var selectedShapeID: Markup.ID?
}

extension EditorSnapshot: Equatable {
    /// Two snapshots are equal when the *document* is equal. Selection is
    /// deliberately excluded: selecting a marker isn't an edit, so an action
    /// that only moves the selection around must not push an undo entry.
    ///
    /// Images compare by identity — pixel comparison would be pointless work,
    /// and every image change in the editor comes from a crop, which always
    /// produces a new instance.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.image === rhs.image
            && lhs.pins == rhs.pins
            && lhs.shapes == rhs.shapes
            && lhs.context == rhs.context
    }
}

/// Bounded undo/redo stacks of editor snapshots.
///
/// A value type held in `@State` by `EditorView`: mutating it re-renders the
/// toolbar buttons, so `canUndo`/`canRedo` stay in sync with the stacks for
/// free. Every entry is the state to go *back* to, recorded just before the
/// mutation that changed it.
struct EditorHistory {
    /// Enough to cover a long annotation session while keeping the retained
    /// images bounded (a crop keeps its pre-crop image alive as long as its
    /// entry lives).
    static let limit = 50

    private(set) var undoStack: [EditorSnapshot] = []
    private(set) var redoStack: [EditorSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Pushes the pre-mutation state. Drops the oldest entry past `limit`, and
    /// clears the redo stack — a new edit forks the timeline.
    mutating func record(_ snapshot: EditorSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > Self.limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Returns the state to restore, moving `current` onto the redo stack.
    mutating func undo(current: EditorSnapshot) -> EditorSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Returns the state to restore, moving `current` back onto the undo stack.
    /// Bypasses `record`, which would wipe the redo stack it is walking.
    mutating func redo(current: EditorSnapshot) -> EditorSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
