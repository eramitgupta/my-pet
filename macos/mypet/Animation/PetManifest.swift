import CPetCore
import Foundation

/// The five animations every pet provides, in `PET_STATE_*` order.
enum PetAnimation: String, CaseIterable {
    case idle, walk, run, jump, sleep

    init(state: PetStateKind) {
        self = PetAnimation.allCases[Int(state.rawValue)]
    }
}

/// `manifest.json` inside a pet folder. See README "Adding a pet".
struct PetManifest: Decodable, Equatable {
    struct Animation: Decodable, Equatable {
        var frames: Int
        var fps: Double
        var loop: Bool
    }

    var id: String
    var displayName: String
    var frameSize: [Int]
    var baseColor: String?
    var animations: [String: Animation]
    var menuBarAnimation: String?

    enum ValidationError: Error, CustomStringConvertible {
        case badID, badFrameSize, missingAnimation(String), badAnimation(String)
        var description: String {
            switch self {
            case .badID: return "id must be non-empty"
            case .badFrameSize: return "frameSize must be two positive integers ≤ 256"
            case .missingAnimation(let a): return "missing animation \"\(a)\""
            case .badAnimation(let a): return "animation \"\(a)\" needs 1–64 frames and 0–60 fps"
            }
        }
    }

    func validate() throws {
        guard !id.isEmpty, !id.contains("/") else { throw ValidationError.badID }
        guard frameSize.count == 2, frameSize.allSatisfy({ (1...256).contains($0) }) else {
            throw ValidationError.badFrameSize
        }
        for a in PetAnimation.allCases {
            guard let spec = animations[a.rawValue] else { throw ValidationError.missingAnimation(a.rawValue) }
            guard (1...64).contains(spec.frames), spec.fps > 0, spec.fps <= 60 else {
                throw ValidationError.badAnimation(a.rawValue)
            }
        }
    }

    var frameWidth: Int { frameSize[0] }
    var frameHeight: Int { frameSize[1] }

    /// Animation specs for Rust, indexed by PET_STATE_*.
    var animSpecs: [PetAnimSpec] {
        PetAnimation.allCases.map { a in
            let s = animations[a.rawValue]!
            return PetAnimSpec(frames: UInt32(s.frames), fps: Float(s.fps), looping: s.loop ? 1 : 0)
        }
    }

    var menuBar: PetAnimation { menuBarAnimation.flatMap(PetAnimation.init(rawValue:)) ?? .run }
}
