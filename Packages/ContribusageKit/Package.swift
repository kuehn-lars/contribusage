// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ContribusageKit",
    // English first; user facing strings live in String Catalogs (NFR-10).
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ContribusageCore", targets: ["ContribusageCore"]),
        .library(name: "ContribusageClaudeCode", targets: ["ContribusageClaudeCode"]),
        .library(name: "ContribusageGitHub", targets: ["ContribusageGitHub"]),
    ],
    targets: [
        // Provider neutral core. Must never depend on a provider or on GitHub (NFR-17).
        // Resources declared explicitly: older SwiftPM (Xcode 26) leaves an undeclared String Catalog unhandled.
        .target(name: "ContribusageCore", resources: [.process("Resources")]),

        // Providers. Each depends only on the core.
        .target(name: "ContribusageClaudeCode", dependencies: ["ContribusageCore"], resources: [.process("Resources")]),

        // GitHub contributions.
        .target(name: "ContribusageGitHub", dependencies: ["ContribusageCore"]),

        // Shared fakes, FakeProvider and the provider conformance suite (not shipped).
        .target(
            name: "ContribusageTestSupport",
            dependencies: ["ContribusageCore"],
            path: "Tests/ContribusageTestSupport"
        ),

        // Test targets get `resources: [.copy("Fixtures")]` with their first fixture (SPEC §16.2).
        .testTarget(
            name: "ContribusageCoreTests",
            dependencies: ["ContribusageCore", "ContribusageTestSupport"]
        ),
        .testTarget(
            name: "ContribusageClaudeCodeTests",
            dependencies: ["ContribusageClaudeCode", "ContribusageTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ContribusageGitHubTests",
            dependencies: ["ContribusageGitHub", "ContribusageTestSupport"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
