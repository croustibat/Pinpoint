import AppKit

/// The eight resize handles of an adjustable rectangle: four corners plus four
/// edge midpoints.
///
/// This mirrors `CropOverlay`'s handle semantics in the editor so both surfaces
/// behave the same way — a corner moves two edges, an edge handle moves one,
/// free aspect ratio, a minimum side is enforced. The two can't share a type as
/// is: the crop overlay works on a normalized SwiftUI rect (top-left origin),
/// this one on view-local AppKit points. Geometry here is therefore expressed
/// in AppKit's default bottom-left origin space (`RegionSelectionView` isn't
/// flipped), so `top` means the *larger* `y`.
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Where the handle sits on `rect`.
    func point(in rect: CGRect) -> CGPoint {
        switch self {
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
    static func hit(_ point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> SelectionHandle? {
        let ordered: [SelectionHandle] = [
            .topLeft, .topRight, .bottomRight, .bottomLeft,  // corners first
            .top, .right, .bottom, .left
        ]
        return ordered.first { handle in
            let p = handle.point(in: rect)
            return abs(point.x - p.x) <= tolerance && abs(point.y - p.y) <= tolerance
        }
    }

    /// Applies `dx`/`dy` to the edges this handle owns and returns the new rect,
    /// never thinner than `minSide` on either axis and never leaving `bounds`.
    ///
    /// Built from explicit x/y/width/height because `CGRect`'s `minX`/`maxX` are
    /// read-only, same as the editor's crop overlay.
    func resize(_ rect: CGRect, dx: CGFloat, dy: CGFloat, minSide: CGFloat, in bounds: CGRect) -> CGRect {
        var x = rect.minX
        var y = rect.minY
        var w = rect.width
        var h = rect.height

        switch self {
        case .topLeft, .left, .bottomLeft:            // left edge
            let nx = min(max(bounds.minX, x + dx), x + w - minSide)
            w += x - nx
            x = nx
        default: break
        }
        switch self {
        case .topRight, .right, .bottomRight:         // right edge
            w = max(minSide, min(x + w + dx, bounds.maxX) - x)
        default: break
        }
        switch self {
        case .bottomLeft, .bottom, .bottomRight:      // bottom edge (smaller y)
            let ny = min(max(bounds.minY, y + dy), y + h - minSide)
            h += y - ny
            y = ny
        default: break
        }
        switch self {
        case .topLeft, .top, .topRight:               // top edge (larger y)
            h = max(minSide, min(y + h + dy, bounds.maxY) - y)
        default: break
        }

        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Translates `rect` by `dx`/`dy`, keeping it fully inside `bounds` (the
    /// rect keeps its size and slides along the edge it runs into).
    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, in bounds: CGRect) -> CGRect {
        var moved = rect
        moved.origin.x = min(max(bounds.minX, rect.minX + dx), max(bounds.minX, bounds.maxX - rect.width))
        moved.origin.y = min(max(bounds.minY, rect.minY + dy), max(bounds.minY, bounds.maxY - rect.height))
        return moved
    }

    /// The matching system frame-resize cursor, so a handle looks like one.
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
