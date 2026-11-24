// swift-tools-version: 6.2
// SynthRef (spec 22): synthetic native references for evaluation only. Generates TTS references (ElevenLabs by
// default, Mac Premium voices as the labelled fallback), verifies each voice's stress control, runs the end-to-end
// check (ii) path and builds the synthetic edited-native negative set. A separate package on purpose: the app and
// AccentKit's library products never link it (scripts/check-no-tts-in-app.sh). No dependency beyond AccentKit.
import PackageDescription

let package = Package(
    name: "SynthRef",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "synthref", targets: ["synthref"]),
    ],
    dependencies: [
        .package(name: "AccentKit", path: "../../Packages/AccentKit"),
    ],
    targets: [
        .target(
            name: "SynthRefKit",
            dependencies: [
                .product(name: "AMCore", package: "AccentKit"),
                .product(name: "AMAlignment", package: "AccentKit"),
                .product(name: "AMProsody", package: "AccentKit"),
                .product(name: "AMCapture", package: "AccentKit"),
                .product(name: "AMPitch", package: "AccentKit"),
                .product(name: "AMScoring", package: "AccentKit"),
                .product(name: "AMPipeline", package: "AccentKit"),
                .product(name: "AMEvaluation", package: "AccentKit"),
            ]
        ),
        .executableTarget(name: "synthref", dependencies: ["SynthRefKit"]),
        .testTarget(name: "SynthRefKitTests", dependencies: ["SynthRefKit"]),
    ],
    swiftLanguageModes: [.v6]
)
