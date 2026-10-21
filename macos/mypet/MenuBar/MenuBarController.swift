import AppKit
import CPetCore
import SwiftUI

/// The animated pet in the menu bar plus its dropdown.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let makePopoverContent: () -> AnyView
    private let library: SpriteLibrary
    private var animator: SpriteAnimator?
    private var ticker: FrameTicker!
    private var settings = PetSettings()
    private var maxFPS: Double?
    private var running = false
    private var occlusionObserver: NSObjectProtocol?

    /// Called when menu-bar visibility or the popover's open state changes.
    var onStateChange: (() -> Void)?
    /// False while a full-screen app or an auto-hidden menu bar hides the pet. Starts true
    /// and follows occlusion notifications only: the very first occlusion reading, taken
    /// before the menu bar has composited, is "hidden" even though the item is about to show.
    private(set) var isMenuBarVisible = true
    var isPopoverShown: Bool { popover.isShown }
    private var facing = FacingController()

    // Rendering state
    private var shownImage: CGImage?
    private var layout: Layout?
    private let petLayer = CALayer()
    private var placeholderInstalled = false
    private var lastReplicantRefresh: CFTimeInterval = 0
    /// Compatibility path: NSImage per (frame, direction). The CGImage is retained so its
    /// identity can't be reused by a different image while cached.
    private var imageCache: [ImageKey: (CGImage, NSImage)] = [:]

    private struct ImageKey: Hashable {
        let image: ObjectIdentifier
        let mirrored: Bool
    }

    /// Where the pet sits inside each sprite frame, and how big it is drawn. Computed once
    /// per pet instead of every frame.
    private struct Layout {
        let crop: CGRect          // opaque area, in frame pixels (top-left origin)
        let frameSize: CGSize     // full sprite frame, in pixels
        let size: NSSize          // drawn size in points

        /// The crop in CALayer unit coordinates. Whether y runs down or up depends on the
        /// layer's geometry, which AppKit decides (flipped views get flipped layers).
        func contentsRect(flipped: Bool) -> CGRect {
            let w = frameSize.width, h = frameSize.height
            let y = flipped ? crop.minY / h : 1 - crop.maxY / h
            return CGRect(x: crop.minX / w, y: y, width: crop.width / w, height: crop.height / h)
        }
    }

    init<Content: View>(library: SpriteLibrary, popoverContent: @escaping () -> Content) {
        self.library = library
        self.makePopoverContent = { AnyView(popoverContent()) }
        super.init()
        ticker = FrameTicker { [weak self] dt in self?.tick(dt) }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: statusItem.button?.window, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow else { return }
                let visible = window.occlusionState.contains(.visible)
                guard visible != self.isMenuBarVisible else { return }
                self.isMenuBarVisible = visible
                self.onStateChange?()
            }
        }
    }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    // MARK: Settings and state

    func apply(_ s: PetSettings, maxFPS: Double?) {
        guard let sprites = library.pet(s.menuBar.petID) else { return }
        if s.lowCPUMenuBar != settings.lowCPUMenuBar { shownImage = nil }
        if s.facing != facing.mode {
            facing.setMode(s.facing)
            shownImage = nil // redraw now with the new direction
        }
        settings = s
        self.maxFPS = maxFPS

        if animator == nil { animator = SpriteAnimator(sprites: sprites) }
        guard let animator else { return }
        if animator.sprites !== sprites || layout == nil {
            imageCache.removeAll()
            layout = Self.layout(for: sprites)
            placeholderInstalled = false
            shownImage = nil
        }
        animator.apply(s, sprites: sprites, state: PetStateKind(sprites.manifest.menuBar))

        if running { updateTickerRate() } else { showStatic() }
        if shownImage == nil { render(settings.paused ? animator.image(.sleep, frame: 0) : animator.currentImage()) }
    }

    func update(metrics m: PetMetrics) {
        animator?.update(metrics: m)
        let cpu = Int(m.cpu_percent.rounded()), ram = Int(m.ram_used_percent.rounded())
        statusItem.button?.toolTip = "\(AppInfo.name) — CPU \(cpu)% · Memory \(ram)% · Pressure \(m.pressureLevel.rawValue)"
        statusItem.button?.setAccessibilityLabel(
            "\(AppInfo.name) \(animator?.sprites.name ?? ""). CPU \(cpu) percent, memory \(ram) percent.")
    }

    func setRunning(_ run: Bool) {
        running = run
        if run { updateTickerRate() } else { ticker.stop(); showStatic() }
    }

    private func showStatic() {
        guard let animator, settings.paused else { return }
        render(animator.image(.sleep, frame: 0))
    }

    private func updateTickerRate() {
        guard let animator else { return }
        var interval = animator.spriteInterval
        if let maxFPS { interval = max(interval, 1.0 / maxFPS) }
        ticker.run(interval: interval)
    }

    private func tick(_ dt: Double) {
        guard let animator else { return }
        if facing.advance(dt) { shownImage = nil }
        render(animator.tick(dt: dt))
        updateTickerRate()
    }

    // MARK: Rendering

    private func render(_ cg: CGImage) {
        guard cg !== shownImage, let layout, let button = statusItem.button else { return }
        shownImage = cg
        if settings.lowCPUMenuBar {
            renderLayer(cg, layout, in: button)
        } else {
            renderImage(cg, layout, in: button)
        }
    }

    /// Default path: swap a sublayer's contents. Setting `button.image` instead makes AppKit
    /// redraw the button and re-snapshot it for every menu bar ("replicants"), measured at
    /// ~10× the CPU. `contentsRect` shows just the pet's area, so no per-frame crop is made.
    private func renderLayer(_ cg: CGImage, _ layout: Layout, in button: NSStatusBarButton) {
        if !placeholderInstalled || petLayer.superlayer == nil {
            button.wantsLayer = true
            petLayer.magnificationFilter = .nearest
            petLayer.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(),
                                "position": NSNull(), "transform": NSNull()]
            if petLayer.superlayer == nil { button.layer?.addSublayer(petLayer) }
            button.image = NSImage(size: layout.size) // transparent; reserves the item's width
            placeholderInstalled = true
        }
        // bounds + position (not frame) so the mirror transform flips around the centre.
        petLayer.bounds = CGRect(origin: .zero, size: layout.size)
        petLayer.position = CGPoint(x: ((button.bounds.width - layout.size.width) / 2).rounded() + layout.size.width / 2,
                                    y: ((button.bounds.height - layout.size.height) / 2).rounded() + layout.size.height / 2)
        petLayer.transform = facing.facingLeft ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        petLayer.contentsScale = button.window?.backingScaleFactor ?? 2
        petLayer.contentsRect = layout.contentsRect(flipped: petLayer.contentsAreFlipped())
        petLayer.contents = cg
        refreshReplicantsIfDue(button, layout)
    }

    /// Fallback path (Settings → General → Low-CPU menu bar animation off).
    private func renderImage(_ cg: CGImage, _ layout: Layout, in button: NSStatusBarButton) {
        if petLayer.superlayer != nil {
            petLayer.removeFromSuperlayer()
            placeholderInstalled = false
        }
        let key = ImageKey(image: ObjectIdentifier(cg), mirrored: facing.facingLeft)
        let image: NSImage
        if let hit = imageCache[key] {
            image = hit.1
        } else {
            let crop = cg.cropping(to: layout.crop) ?? cg
            image = Self.menuBarImage(crop, size: layout.size, mirrored: facing.facingLeft)
            if imageCache.count > 96 { imageCache.removeAll(keepingCapacity: true) }
            imageCache[key] = (cg, image)
        }
        button.image = image
    }

    /// Menu bars on other displays show snapshots of the button. Re-snapshot every few
    /// seconds so they follow the pet's colour and pose without paying the per-frame cost.
    private func refreshReplicantsIfDue(_ button: NSStatusBarButton, _ layout: Layout) {
        let now = CACurrentMediaTime()
        guard now - lastReplicantRefresh > 3 else { return }
        lastReplicantRefresh = now
        button.image = NSImage(size: layout.size)
    }

    private static func layout(for sprites: PetSprites) -> Layout {
        let w = CGFloat(sprites.manifest.frameWidth), h = CGFloat(sprites.manifest.frameHeight)
        let crop = sprites.contentBounds[sprites.manifest.menuBar] ?? CGRect(x: 0, y: 0, width: w, height: h)
        let height = min(18, NSStatusBar.system.thickness - 4)
        let size = NSSize(width: (crop.width * height / crop.height).rounded(), height: height)
        return Layout(crop: crop, frameSize: CGSize(width: w, height: h), size: size)
    }

    /// The cropped frame as an NSImage drawn without smoothing.
    static func menuBarImage(_ crop: CGImage, size: NSSize, mirrored: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current else { return false }
            ctx.imageInterpolation = .none
            ctx.cgContext.interpolationQuality = .none
            if mirrored {
                ctx.cgContext.translateBy(x: rect.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
            }
            ctx.cgContext.draw(crop, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            // Built on demand and released on close, so a closed popover costs nothing
            // when metrics update.
            popover.contentViewController = NSHostingController(rootView: makePopoverContent())
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() { popover.performClose(nil) }

    func popoverDidShow(_ notification: Notification) {
        onStateChange?()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        onStateChange?()
    }
}

extension PetStateKind {
    init(_ animation: PetAnimation) {
        self = PetStateKind(rawValue: UInt8(PetAnimation.allCases.firstIndex(of: animation) ?? 2)) ?? .run
    }
}
