import CPetCore
import Foundation

/// Latest metrics for the UI. Main-thread only; the only object views subscribe to.
@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var latest: PetMetrics?

    func publish(_ m: PetMetrics) { latest = m }
}
