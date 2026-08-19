import CoreGraphics

/// Every drawn dimension of an annotation — stroke widths, badge radius,
/// arrowhead length — derived from the capture's width, so the editor preview
/// and the exported image show the same annotation at the same relative size.
///
/// The formulas are written in *image space*: the pixel grid `Exporter` draws
/// into, where the same marker is genuinely larger on a 3840 px capture than on
/// a 400 px one. `scale` then maps them into whatever space the caller draws in.
/// The exporter renders the capture at 1:1 and leaves `scale` at 1; the editor
/// renders it into the fitted rect and passes `fitted.width / image.size.width`,
/// so its annotations shrink and grow by exactly the amount the preview itself
/// does.
///
/// Before this type the editor drew at fixed point sizes (a 28 pt badge, a
/// 3.5 pt stroke) while the exporter scaled with the image, so the export of a
/// small capture came out far heavier than its preview (#48). Keeping both
/// sides on one set of formulas is what makes the preview WYSIWYG — and what
/// keeps the two `clampedMarkerAnchor` implementations agreeing on where a
/// badge near an edge lands (#34/#35).
///
/// Note the floors (`max(3, …)`, `max(16, …)`): they are expressed in image
/// pixels, so a Retina capture — whose `size` is its pixel count, twice the
/// points it covered on screen — clears them where the 1x capture of the same
/// region would be held at the floor. That is the exporter's long-standing
/// behaviour; the preview now reproduces it instead of hiding it.
struct MarkupMetrics {
    /// The capture's width in image space (pixels). Never below 1, so the
    /// derived sizes stay finite for a degenerate image.
    let imageWidth: CGFloat
    /// Image space → drawing space. 1 when drawing the capture at full size.
    let scale: CGFloat

    init(imageWidth: CGFloat, scale: CGFloat = 1) {
        self.imageWidth = max(1, imageWidth)
        self.scale = scale.isFinite && scale > 0 ? scale : 1
    }

    /// Metrics for a preview of `imageSize` drawn into `fitted` — the editor
    /// canvas. Falls back to 1:1 for a degenerate size, since a canvas that
    /// hasn't been laid out yet reports a zero-width rect.
    init(imageSize: CGSize, fitted: CGRect) {
        self.init(imageWidth: imageSize.width,
                  scale: imageSize.width > 0 ? fitted.width / imageSize.width : 1)
    }

    // MARK: - Shapes

    /// Stroke width of arrows and rectangles.
    var lineWidth: CGFloat { max(3, imageWidth * 0.004) * scale }

    /// Corner radius of a rectangle markup. Tied to the stroke width, which is
    /// what the exporter has always rounded its rectangles by.
    var cornerRadius: CGFloat { lineWidth }

    /// Length of the two strokes forming an arrow's head.
    var arrowHeadLength: CGFloat { max(14, imageWidth * 0.018) * scale }

    /// Half-angle between an arrow's shaft and each of its head strokes.
    static let arrowHeadSpread = CGFloat.pi / 6.5

    // MARK: - Markers

    /// The badge radius in image space, before `scale`. The ring's own floor is
    /// expressed against this, so it has to stay unscaled.
    private var imagePinRadius: CGFloat { max(16, imageWidth * 0.014) }

    /// Radius of a marker's badge — of its head, in the pointer style.
    var pinRadius: CGFloat { imagePinRadius * scale }

    /// Width of the ring drawn around a badge.
    var ringWidth: CGFloat { max(2, imagePinRadius * 0.16) * scale }

    /// Point size of the number inside a badge.
    var numberFontSize: CGFloat { pinRadius * 1.05 }

    /// How far a marker's badge extends from its anchor on either side, ring
    /// included: the margin `clampedMarkerAnchor` keeps it inside the image by.
    var badgeHalfSide: CGFloat { pinRadius + ringWidth }

    /// Distance from a pointer's tip to the centre of its head.
    var pointerHeadOffset: CGFloat { pinRadius * 2 }

    /// Total height of a pointer marker, from its tip to the top of its head.
    var pointerHeight: CGFloat { pinRadius * 3 }
}
