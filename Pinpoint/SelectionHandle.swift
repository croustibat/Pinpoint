import AppKit

/// The eight resize handles of an adjustable rectangle: four corners plus four
/// edge midpoints.
///
/// This mirrors `CropOverlay`'s handle semantics so every adjustable rectangle
/// in the app behaves the same way — a corner moves two edges, an edge handle
/// moves one, free aspect ratio, a minimum side is enforced. Two surfaces use
/// it, in opposite vertical conventions: the capture overlay works in an
/// unflipped `NSView` (bottom-left origin) and the editor canvas in SwiftUI
/// (top-left origin), so every geometry call takes an `Orientation`. The
/// geometry itself is written in `.yUp` terms, which is the default — the
/// AppKit caller reads exactly as it did before.
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Which way "up" runs in the coordinate space a call is working in.
    ///
    /// Handle names describe what the user sees, not a sign convention: the
    /// same `.topLeft` has to land on the smaller `y` in SwiftUI and on the
    /// larger one in an unflipped `NSView`.
    enum Orientation {
        /// Bottom-left origin — AppKit's unflipped views (`RegionSelectionView`).
        case yUp
        /// Top-left origin — SwiftUI, and the normalized image space the editor
        /// stores annotations in.
        case yDown
    }

    /// The handle owning the same *edges* once the vertical axis is flipped.
    /// Only the vertical component moves; `left`/`right` own no horizontal
    /// mirror image and stay put.
    private var verticallyMirrored: SelectionHandle {
        switch self {
        case .topLeft:     return .bottomLeft
        case .top:         return .bottom
        case .topRight:    return .bottomRight
        case .bottomRight: return .topRight
        case .bottom:      return .top
        case .bottomLeft:  return .topLeft
        case .right, .left: return self
        }
    }

    /// The handle to compute with, given the caller's convention.
    private func resolved(_ orientation: Orientation) -> SelectionHandle {
        orientation == .yUp ? self : verticallyMirrored
    }

    /// Where the handle sits on `rect`.
    func point(in rect: CGRect, orientation: Orientation = .yUp) -> CGPoint {
        switch resolved(orientation) {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.maxY)
        case .top:         return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.minY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// The handle whose hit area contains `point`, or `nil` if none does.
    ///
    /// Corners are tested before edges: on a small rect their hit areas overlap,
    /// and a corner (two edges at once) is the more useful of the two.
    static func hit(_ point: CGPoint, in rect: CGRect, tolerance: CGFloat,
                    orientation: Orientation = .yUp) -> SelectionHandle? {
        let ordered: [SelectionHandle] = [
            .topLeft, .topRight, .bottomRight, .bottomLeft,  // corners first
            .top, .right, .bottom, .left
        ]
        return ordered.first { handle in
            let p = handle.point(in: rect, orientation: orientation)
            return abs(point.x - p.x) <= tolerance && abs(point.y - p.y) <= tolerance
        }
    }

    /// Applies `dx`/`dy` to the edges this handle owns and returns the new rect,
    /// never thinner than `minSide` on either axis and never leaving `bounds`.
    ///
    /// Built from explicit x/y/width/height because `CGRect`'s `minX`/`maxX` are
    /// read-only, same as the editor's crop overlay. The deltas are taken in the
    /// caller's own space, so a `.yDown` caller passes the translation it got
    /// from SwiftUI unchanged: mirroring the handle is enough, because each
    /// branch below owns a `min`/`max` *edge*, not a screen direction.
    func resize(_ rect: CGRect, dx: CGFloat, dy: CGFloat, minSide: CGFloat, in bounds: CGRect,
                orientation: Orientation = .yUp) -> CGRect {
        let handle = resolved(orientation)
        var x = rect.minX
        var y = rect.minY
        var w = rect.width
        var h = rect.height

        switch handle {
        case .topLeft, .left, .bottomLeft:            // left edge
            let nx = min(max(bounds.minX, x + dx), x + w - minSide)
            w += x - nx
            x = nx
        default: break
        }
        switch handle {
        case .topRight, .right, .bottomRight:         // right edge
            w = max(minSide, min(x + w + dx, bounds.maxX) - x)
        default: break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:      // bottom edge (smaller y)
            let ny = min(max(bounds.minY, y + dy), y + h - minSide)
            h += y - ny
            y = ny
        default: break
        }
        switch handle {
        case .topLeft, .top, .topRight:               // top edge (larger y)
            h = max(minSide, min(y + h + dy, bounds.maxY) - y)
        default: break
        }

        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Translates `rect` by `dx`/`dy`, keeping it fully inside `bounds` (the
    /// rect keeps its size and slides along the edge it runs into). Orientation
    /// free: it moves both edges of each axis by the same amount.
    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, in bounds: CGRect) -> CGRect {
        var moved = rect
        moved.origin.x = min(max(bounds.minX, rect.minX + dx), max(bounds.minX, bounds.maxX - rect.width))
        moved.origin.y = min(max(bounds.minY, rect.minY + dy), max(bounds.minY, bounds.maxY - rect.height))
        return moved
    }

    /// The matching system frame-resize cursor, so a handle looks like one.
    /// Orientation free: the cases are named for what the user sees, and so are
    /// AppKit's cursor positions.
    var cursor: NSCursor {
        switch self {
        case .topLeft:     return .frameResize(position: .topLeft, directions: .all)
        case .top:         return .frameResize(position: .top, directions: .all)
        case .topRight:    return .frameResize(position: .topRight, directions: .all)
        case .right:       return .frameResize(position: .right, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        case .bottom:      return .frameResize(position: .bottom, directions: .all)
        case .bottomLeft:  return .frameResize(position: .bottomLeft, directions: .all)
        case .left:        return .frameResize(position: .left, directions: .all)
        }
    }
}
