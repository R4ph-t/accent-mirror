// swift-tools-version: 6.2
// AccentKit: all of Accent Mirror's logic, platform-neutral (no AppKit, no UIKit).
// Dependencies point inward to AMCore; see AGENTS.md for the module map.
import PackageDescription

let modules: [(name: String, dependencies: [String])] = [
    ("AMCore", []),
    ("AMCapture", ["AMCore"]),
    ("AMAlignment", ["AMCore"]),
    ("AMPitch", ["AMCore"]),
    ("AMProsody", ["AMCore", "AMAlignment", "AMPitch"]),
    ("AMWarp", ["AMCore", "AMPitch"]),
    ("AMScoring", ["AMCore", "AMProsody", "AMWarp"]),
    ("AMLibrary", ["AMCore"]),
    ("AMPipeline", ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody", "AMWarp", "AMScoring", "AMLibrary"]),
]

/// Third-party products a module links, by module name.
/// WhisperKit (Argmax, MIT): on-device word timestamps, the plan's chosen ASR (spec 03). Pinned to a released
/// version; its weights are fetched separately and SHA-256 checked (Resources/Models/).
let externalDependencies: [String: [Target.Dependency]] = [
    "AMAlignment": [.product(name: "WhisperKit", package: "WhisperKit")],
]

let package = Package(
    name: "AccentKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) },
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies.map { .target(name: $0) } + (externalDependencies[module.name] ?? [])
            ),
            .testTarget(
                name: "\(module.name)Tests",
                dependencies: [.target(name: module.name)]
            ),
        ]
    } + [
        // Local evaluation tooling (spec 03): never linked into the app, never run by CI.
        .target(name: "AMTimestampEval", dependencies: ["AMAlignment"]),
        .testTarget(name: "AMTimestampEvalTests", dependencies: ["AMTimestampEval"]),
        .executableTarget(name: "am-timestamps", dependencies: ["AMTimestampEval", "AMAlignment"]),
    ],
    swiftLanguageModes: [.v6]
)
