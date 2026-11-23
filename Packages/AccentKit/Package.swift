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
    // Evaluation only (spec 02): manifests, folds, statistics and the reporter. The app never links it.
    ("AMEvaluation", ["AMCore"]),
]

let package = Package(
    name: "AccentKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) }
        + [.executable(name: "am-eval", targets: ["am-eval"])],
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies.map { .target(name: $0) },
                // AMAlignment bundles CMUdict and its word lists (spec 06), copied verbatim.
                resources: module.name == "AMAlignment" ? [.copy("Resources")] : nil
            ),
            .testTarget(
                name: "\(module.name)Tests",
                dependencies: [.target(name: module.name)],
                // AMCore's golden JSON is read from the source tree by path (spec 01), not bundled.
                exclude: module.name == "AMCore" ? ["Golden"] : [],
                resources: module.name == "AMAlignment" ? [.copy("Fixtures")] : nil
            ),
        ]
    } + [
        // The agreement harness's command-line runner (spec 02), called by scripts/agreement.sh and friends. Tool
        // only: the app target depends on AMPipeline alone and never links this or AMEvaluation.
        .executableTarget(
            name: "am-eval",
            dependencies: [.target(name: "AMPipeline"), .target(name: "AMEvaluation")],
            path: "Sources/am-eval"
        ),
    ],
    swiftLanguageModes: [.v6]
)
