import Foundation

/// App-wide constants. User-facing names come from `AppInfo`; URLs from `ProjectLinks`.
enum AppInfo {
    /// The name people see (Finder, Spotlight, menus). Identifiers stay lowercase: com.erag.mypet.
    static let name = "MyPet"
    static let tagline = "Your Mac’s Little Companion."
}

enum ProjectLinks {
    static let author = URL(string: "https://github.com/eramitgupta")!
    static let sponsor = URL(string: "https://github.com/sponsors/eramitgupta")!
}
