import AppKit
import CPetCore
import SwiftUI

/// A live pet inside SwiftUI, rendered through the same SpriteAnimator/TintRenderer path as
/// the real pets. Its timer runs only while the view is in a visible window.
struct AnimatedPetPreview: NSViewRepresentable {
    let petID: String
    var state: PetStateKind = .run
    /// False shows a single still frame with no timer (gallery cards that aren't in focus).
    var animated = true
    var settings: PetSettings
    var metrics: PetMetrics?
    var facing: PetFacing = .right

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PreviewHostView {
        let v = PreviewHostView(frame: .zero)
        v.coordinator = context.coordinator
        context.coordinator.view = v
        context.coordinator.configure(self)
        return v
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        context.coordinator.configure(self)
    }

    static func dismantleNSView(_ nsView: PreviewHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        weak var view: PreviewHostView?
        private var animator: SpriteAnimator?
        private lazy var ticker = FrameTicker { [weak self] dt in self?.tick(dt) }
        private var lastMetrics: PetMetrics?
        private var facing = FacingController()
        private var animated = true

        func configure(_ p: AnimatedPetPreview) {
            guard let sprites = SpriteLibrary.shared.pet(p.petID) else { return }
            if animator == nil { animator = SpriteAnimator(sprites: sprites) }
            guard let animator else { return }
            animator.apply(p.settings, sprites: sprites, state: p.state)
            if let m = p.metrics, m.cpu_percent != lastMetrics?.cpu_percent || m.ram_used_percent != lastMetrics?.ram_used_percent {
                animator.update(metrics: m)
                lastMetrics = m
            }
            if p.facing != facing.mode { facing.setMode(p.facing) }
            animated = p.animated
            // A still card shows the first frame; an animated one continues where it was.
            let image = animated ? animator.tick(dt: 0) : animator.image(PetAnimation(state: p.state), frame: 0)
            view?.sprite.show(image, facingLeft: facing.facingLeft)
            visibilityChanged()
        }

        func visibilityChanged() {
            if animated, view?.window?.occlusionState.contains(.visible) == true { start() } else { stop() }
        }

        func start() {
            guard let animator else { return }
            ticker.run(interval: animator.spriteInterval)
        }

        func stop() { ticker.stop() }

        private func tick(_ dt: Double) {
            guard let animator, let view else { return }
            _ = facing.advance(dt)
            view.sprite.show(animator.tick(dt: dt), facingLeft: facing.facingLeft)
            ticker.run(interval: animator.spriteInterval)
        }
    }
}

/// Hosts the sprite view and tells the coordinator when it enters or leaves a window.
final class PreviewHostView: NSView {
    let sprite = PetSpriteView(frame: .zero)
    weak var coordinator: AnimatedPetPreview.Coordinator?
    private var occlusionObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        sprite.autoresizingMask = [.width, .height]
        addSubview(sprite)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        sprite.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinator?.visibilityChanged() }
            }
        }
        coordinator?.visibilityChanged()
    }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
}
