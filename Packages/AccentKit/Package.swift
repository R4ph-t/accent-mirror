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

let package = Package(
    name: "AccentKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) },
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies.map { .target(name: $0) }
            ),
            .testTarget(
                name: "\(module.name)Tests",
                dependencies: [.target(name: module.name)]
            ),
        ]
    },
    swiftLanguageModes: [.v6]
)
