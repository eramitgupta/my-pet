import Combine
import Foundation

/// Single source of truth for user preferences. Changes are applied live by observers and
/// written to UserDefaults after a short debounce (slider drags don't hammer the disk).
@MainActor
final class SettingsStore: ObservableObject {
    static let storageKey = "settings.v1"
    /// Bundle ID used before the app was renamed to mypet; its settings are copied over once.
    nonisolated static let legacyDomain = "app.macpet" + ".MacPet"

    @Published var settings: PetSettings {
        didSet {
            let clean = settings.sanitized
            if clean != settings {
                settings = clean // re-enters didSet once with valid values
                return
            }
            scheduleSave()
        }
    }

    private let defaults: UserDefaults
    private var pendingSave: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard { Self.migrateLegacySettings(into: defaults) }
        settings = Self.load(from: defaults)
    }

    /// One-time copy of settings saved under the pre-rename bundle ID.
    static func migrateLegacySettings(into defaults: UserDefaults, legacy: UserDefaults? = UserDefaults(suiteName: legacyDomain)) {
        guard defaults.data(forKey: storageKey) == nil,
              let old = legacy?.data(forKey: storageKey) else { return }
        defaults.set(old, forKey: storageKey)
    }

    static func load(from defaults: UserDefaults) -> PetSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(PetSettings.self, from: data)
        else { return PetSettings() }
        return decoded.sanitized
    }

    func update(_ change: (inout PetSettings) -> Void) {
        var s = settings
        change(&s)
        if s != settings { settings = s }
    }

    func resetToDefaults() {
        settings = PetSettings()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// Writes immediately (called on quit).
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
