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
    // Spec 28: the verdict path, out of the shipped graph. AMPlacement is the leaf holding observed stress, A(w) and
    // the placement rule; AMScoring and AMVerdicts build on it. AMPipeline (what the app links) reaches none of the
    // three (ShippedGraphTests).
    ("AMPlacement", ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody"]),
    ("AMScoring", ["AMCore", "AMProsody", "AMWarp", "AMPlacement"]),
    ("AMLibrary", ["AMCore"]),
    // Per-sound pronunciation judging (sound-judging plan, 2026-11-25): Core ML GOP. AMCore and Apple frameworks only.
    ("AMJudging", ["AMCore"]),
    ("AMPipeline", ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody", "AMWarp", "AMLibrary", "AMJudging"]),
    // The verdict scorer (`VerdictScorer`), pair scoring and the placement goldens. Evaluation and Milestone 2 only.
    ("AMVerdicts", ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody", "AMWarp", "AMPlacement", "AMScoring",
                    "AMPipeline"]),
    // Evaluation only (spec 02): manifests, folds, statistics and the reporter. The app never links it.
    ("AMEvaluation", ["AMCore"]),
]

/// Third-party products a module links, by module name.
/// WhisperKit (Argmax, MIT): on-device word timestamps, the plan's chosen ASR (spec 03). Pinned to a released
/// version; its weights are fetched separately and SHA-256 checked (Resources/Models/).
let externalDependencies: [String: [Target.Dependency]] = [
    "AMAlignment": [.product(name: "WhisperKit", package: "WhisperKit")],
]

/// Extra modules a test target links beyond its own. AMPipelineTests also links AMVerdicts (spec 28): the scoring-off
/// tests compare the shipped run with a `VerdictScorer` run, and the smoke and pipeline goldens pin `VerdictScorer`.
/// Test-only: AMPipeline itself never depends on AMVerdicts (ShippedGraphTests).
let extraTestDependencies: [String: [String]] = [
    "AMPipeline": ["AMVerdicts"],
]

let package = Package(
    name: "AccentKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) }
        + [.executable(name: "am-eval", targets: ["am-eval"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies.map { .target(name: $0) } + (externalDependencies[module.name] ?? []),
                // AMAlignment bundles CMUdict and its word lists (spec 06), copied verbatim.
                resources: module.name == "AMAlignment" ? [.copy("Resources")] : nil
            ),
            .testTarget(
                name: "\(module.name)Tests",
                dependencies: ([module.name] + (extraTestDependencies[module.name] ?? [])).map { .target(name: $0) },
                // AMCore's golden JSON is read from the source tree by path (spec 01), not bundled.
                exclude: module.name == "AMCore" ? ["Golden"] : [],
                resources: module.name == "AMAlignment" ? [.copy("Fixtures")] : nil
            ),
        ]
    } + [
        // The agreement harness's command-line runner (spec 02), called by scripts/agreement.sh and friends. Tool
        // only: the app target depends on AMPipeline alone and never links this or AMEvaluation.
        // Pinned to the verdict scorer (spec 28): evaluation always runs `VerdictScorer()` (EvaluationConfig).
        .executableTarget(
            name: "am-eval",
            dependencies: [.target(name: "AMPipeline"), .target(name: "AMEvaluation"), .target(name: "AMVerdicts")],
            path: "Sources/am-eval"
        ),
        // Local evaluation tooling (spec 03): never linked into the app, never run by CI.
        .target(name: "AMTimestampEval", dependencies: ["AMCore", "AMAlignment"]),
        .testTarget(name: "AMTimestampEvalTests", dependencies: ["AMCore", "AMAlignment", "AMTimestampEval"]),
        // Spec 23's b2 (ctc-w2v2b960-1): evaluation tooling only, never shipped (CTO ruling 2026-11-24 on #27). Not a
        // product and not in `modules`, so AMPipeline (what the app links) can't reach it; only am-timestamps and the
        // tests depend on it. AMPipelineTests' ShippedAlignerTests fails if anything in AMPipeline's closure does.
        .target(name: "AMAlignmentCTC", dependencies: ["AMCore", "AMAlignment"]),
        .testTarget(name: "AMAlignmentCTCTests", dependencies: ["AMCore", "AMAlignment", "AMAlignmentCTC"]),
        // Spec 23 adds the refiners (dsp-snap-1 lives in AMProsody) to the same local tool.
        .executableTarget(name: "am-timestamps",
                          dependencies: ["AMCore", "AMAlignment", "AMAlignmentCTC", "AMCapture", "AMPitch", "AMProsody",
                                         "AMTimestampEval"]),
        // Local evaluation tooling (spec 07): the syllable-boundary report. Never linked into the app, never run by CI.
        .target(name: "AMSyllableEval",
                dependencies: ["AMCore", "AMAlignment", "AMCapture", "AMProsody", "AMTimestampEval"]),
        .testTarget(name: "AMSyllableEvalTests", dependencies: ["AMCore", "AMAlignment", "AMProsody", "AMSyllableEval"]),
        .executableTarget(name: "am-syllables", dependencies: ["AMCore", "AMSyllableEval"]),
        // The live-capture hand check (spec 14, scripts/capture-check.sh): one take from the microphone, nothing
        // saved. Never linked into the app, never run by CI.
        .executableTarget(name: "am-capture", dependencies: ["AMCore", "AMCapture"]),
    ],
    swiftLanguageModes: [.v6]
)
