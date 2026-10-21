import CoreGraphics
import CPetCore
import Foundation

// The only file that calls into libpet_core. Everything else uses these wrappers.
//
// Ownership: each wrapper owns exactly one Rust handle and frees it in deinit.
// Threading: a handle must only be used from one thread at a time. `MetricsEngine` is
// confined to MonitorService's queue; `PetActorHandle`s live on the main thread.

enum RustBridge {
    static var libraryABI: UInt32 { pet_core_abi_version() }
    static let expectedABI = UInt32(PET_CORE_ABI_VERSION)
    static var isCompatible: Bool { libraryABI == expectedABI }

    /// Colour of `value` (0...100) on the four-band gradient, using the same OKLab
    /// interpolation as the pets. Used by the settings preview.
    static func sampleBands(colors: [PetColor], thresholds: [Float], value: Float) -> PetColor? {
        guard colors.count == 4, thresholds.count == 3 else { return nil }
        var out = PetColor()
        let status = colors.withUnsafeBufferPointer { c in
            thresholds.withUnsafeBufferPointer { t in
                pet_gradient_sample_bands(c.baseAddress, t.baseAddress, value, &out)
            }
        }
        return status == PetStatus(PET_OK) ? out : nil
    }
}

/// Shared system sampler (`PetEngine *`).
final class MetricsEngine {
    private let handle: OpaquePointer

    init?() {
        guard let h = pet_engine_new() else { return nil }
        handle = h
    }

    deinit { pet_engine_free(handle) }

    func sample() -> PetMetrics? {
        var m = PetMetrics()
        return pet_engine_sample(handle, &m) == PetStatus(PET_OK) ? m : nil
    }

    func notePressureEvent(level: UInt8) {
        _ = pet_engine_note_pressure_event(handle, level)
    }
}

/// Mirrors `PET_STATE_*`; raw values index a pet's animations.
enum PetStateKind: UInt8, CaseIterable {
    case idle = 0, walk, run, jump, sleep
}

/// Options that map onto `PetActorConfig`.
struct ActorOptions: Equatable {
    var memoryMode: MemoryMode = .usage
    var cpuDrivenSpeed = true
    var manualSpeed: Float = 1
    /// Which animation the pet shows.
    var state: PetStateKind = .run
}

/// One animated pet (`PetActor *`).
final class PetActorHandle {
    private let handle: OpaquePointer

    init?() {
        guard let h = pet_actor_new() else { return nil }
        handle = h
    }

    deinit { pet_actor_free(handle) }

    @discardableResult
    func configure(_ options: ActorOptions, animations: [PetAnimSpec]) -> Bool {
        guard animations.count == Int(PET_STATE_COUNT) else { return false }
        var cfg = PetActorConfig()
        cfg.memory_mode = UInt8(options.memoryMode == .usage ? PET_MEMORY_MODE_USAGE : PET_MEMORY_MODE_PRESSURE)
        cfg.cpu_driven_speed = options.cpuDrivenSpeed ? 1 : 0
        cfg.state = options.state.rawValue
        cfg.manual_speed = options.manualSpeed
        cfg.animations = (animations[0], animations[1], animations[2], animations[3], animations[4])
        return pet_actor_configure(handle, &cfg) == PetStatus(PET_OK)
    }

    @discardableResult
    func setBands(colors: [PetColor], thresholds: [Float]) -> Bool {
        guard colors.count == 4, thresholds.count == 3 else { return false }
        return colors.withUnsafeBufferPointer { c in
            thresholds.withUnsafeBufferPointer { t in
                pet_actor_set_bands(handle, c.baseAddress, t.baseAddress) == PetStatus(PET_OK)
            }
        }
    }

    func update(metrics: PetMetrics) {
        var m = metrics
        _ = pet_actor_update_metrics(handle, &m)
    }

    func tick(dt: Double) -> PetFrame {
        var f = PetFrame()
        _ = pet_actor_tick(handle, dt, &f)
        return f
    }
}

extension PetColor {
    init(_ rgb: RGB) {
        self.init(r: Float(rgb.r), g: Float(rgb.g), b: Float(rgb.b))
    }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

extension PetMetrics {
    var pressureLevel: PressureLevel {
        switch kernel_pressure_level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

enum PressureLevel: String {
    case normal = "Normal", warning = "Warning", critical = "Critical"
}
