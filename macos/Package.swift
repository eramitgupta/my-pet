// swift-tools-version:5.9
// SwiftPM build of mypet, for machines with only the Command Line Tools and for CI.
// Run scripts/build-app.sh rather than `swift build` directly: it builds the Rust library
// first and assembles the .app bundle (Info.plist, assets, icon, signature).
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
let rustConfig = ProcessInfo.processInfo.environment["MYPET_RUST_CONFIG"] ?? "debug"

let package = Package(
    name: "mypet",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "mypet", targets: ["mypet"])],
    dependencies: [
        // The one third-party dependency: Sparkle handles signed, verified app updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .systemLibrary(name: "CPetCore", path: "CPetCore"),
        .executableTarget(
            name: "mypet",
            dependencies: ["CPetCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "mypet",
            exclude: ["Assets", "Info.plist", "mypet.entitlements"],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(root)/target/universal/\(rustConfig)",
                    // Sparkle.framework is embedded in mypet.app/Contents/Frameworks.
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "mypetTests",
            dependencies: ["mypet"],
            path: "Tests/mypetTests"
        ),
    ]
)
