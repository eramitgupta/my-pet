import CoreGraphics
import CPetCore
import Foundation

/// Drives one pet: owns its Rust actor, feeds it metrics, and turns each tick into the
/// image to display. Shared by the menu-bar pet and the settings previews, so all of them
/// render through exactly the same path.
@MainActor
final class SpriteAnimator {
    private let actor: PetActorHandle
    private let renderer: TintRenderer
    private(set) var sprites: PetSprites
    private(set) var options = ActorOptions()
    private(set) var lastFrame = PetFrame()
    private var gradient: (colors: [RGB], thresholds: [Double])?

    /// When false the pet is shown in its own natural colours (manifest `baseColor`).
    var gradientEnabled = true

    init?(sprites: PetSprites, renderer: TintRenderer? = nil) {
        guard let actor = PetActorHandle() else { return nil }
        self.actor = actor
        self.renderer = renderer ?? .shared
        self.sprites = sprites
        actor.configure(options, animations: sprites.manifest.animSpecs)
        lastFrame = actor.tick(dt: 0) // a valid colour and frame before the first timer tick
    }

    /// Applies everything a pet needs from the user's settings. Cheap to call repeatedly:
    /// each part only reaches Rust when it actually changed.
    func apply(_ s: PetSettings, sprites newSprites: PetSprites, state: PetStateKind) {
        if newSprites !== sprites {
            sprites = newSprites
            actor.configure(options, animations: newSprites.manifest.animSpecs)
        }
        let o = ActorOptions(memoryMode: s.memoryMode,
                             cpuDrivenSpeed: s.menuBar.cpuDrivenSpeed,
                             manualSpeed: Float(s.menuBar.manualSpeed),
                             state: state)
        if o != options {
            options = o
            actor.configure(o, animations: sprites.manifest.animSpecs)
        }
        gradientEnabled = s.gradientEnabled
        if gradient?.colors != s.gradientColors || gradient?.thresholds != s.thresholds {
            gradient = (s.gradientColors, s.thresholds)
            actor.setBands(colors: s.gradientColors.map(PetColor.init), thresholds: s.thresholds.map(Float.init))
        }
    }

    func update(metrics: PetMetrics) { actor.update(metrics: metrics) }

    var animation: PetAnimation { PetAnimation(state: options.state) }

    /// Advances the pet and returns the image for this frame.
    func tick(dt: Double) -> CGImage {
        lastFrame = actor.tick(dt: dt)
        return currentImage()
    }

    func currentImage() -> CGImage {
        renderer.image(sprites, animation, Int(lastFrame.frame_index), tint: tint)
    }

    /// A specific frame with the current tint (e.g. a static sleeping pose while paused).
    func image(_ a: PetAnimation, frame: Int) -> CGImage {
        renderer.image(sprites, a, frame, tint: tint)
    }

    private var tint: PetColor? {
        gradientEnabled ? lastFrame.tint : PetColor(sprites.baseColor)
    }

    /// How often to tick so each sprite frame is shown once: fps × speed.
    var spriteInterval: TimeInterval {
        let fps = (sprites.manifest.animations[animation.rawValue]?.fps ?? 8)
            * Double(max(lastFrame.speed_multiplier, 0.25))
        return 1.0 / max(fps, 1)
    }
}
