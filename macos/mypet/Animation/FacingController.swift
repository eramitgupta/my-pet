import Foundation

/// Decides which way a pet faces each tick. In `.turnAround` mode the pet turns at random
/// intervals so it doesn't run the same way forever. Pure value logic, so it's unit-testable
/// and shared by the menu-bar pet and the settings previews.
struct FacingController {
    static let turnInterval: ClosedRange<Double> = 6...14

    private(set) var facingLeft = false
    private(set) var mode: PetFacing
    private var elapsed = 0.0
    private var nextTurn = 0.0
    private let random: () -> Double

    /// `random` returns values in 0..<1; injectable for deterministic tests.
    init(mode: PetFacing = .right, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.mode = mode
        self.random = random
        setMode(mode)
    }

    mutating func setMode(_ m: PetFacing) {
        mode = m
        elapsed = 0
        nextTurn = Self.turnInterval.lowerBound
            + random() * (Self.turnInterval.upperBound - Self.turnInterval.lowerBound)
        switch m {
        case .right: facingLeft = false
        case .left: facingLeft = true
        case .turnAround: break // keep the current direction; the first turn comes later
        }
    }

    /// Advances time; returns true when the direction changed.
    mutating func advance(_ dt: Double) -> Bool {
        guard mode == .turnAround, dt.isFinite, dt > 0 else { return false }
        elapsed += dt
        guard elapsed >= nextTurn else { return false }
        facingLeft.toggle()
        setMode(.turnAround)
        return true
    }
}
