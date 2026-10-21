import AppKit
import QuartzCore

/// Layer-backed view that shows one sprite frame, scaled with nearest-neighbour filtering so
/// pixel art stays crisp. Used by the settings previews.
final class PetSpriteView: NSView {
    private let spriteLayer = CALayer()
    private var shownImage: CGImage?
    private var shownFacingLeft = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(spriteLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        spriteLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Shows a frame; no-ops when nothing changed so Core Animation does no work.
    func show(_ image: CGImage, facingLeft: Bool) {
        guard image !== shownImage || facingLeft != shownFacingLeft else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contents = image
        if facingLeft != shownFacingLeft {
            spriteLayer.transform = facingLeft ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        }
        CATransaction.commit()
        shownImage = image
        shownFacingLeft = facingLeft
    }
}
