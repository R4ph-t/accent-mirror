// Versions (plan §9.1): monotonic integers, not semver. A golden-output digest sits next to them, and
// `GoldenDigestTests` fails if the golden JSON changes without a version bump.

import Foundation

public enum Versions {
    /// Bump when an algorithm change can change any output for the same inputs.
    public static let algorithmVersion = 1
    /// Bump when any value in `Thresholds` changes.
    public static let thresholdsVersion = 6
    /// Bump when a contract type's shape or JSON changes.
    public static let contractVersion = 1

    /// The golden-output digest recorded for one version triple.
    public struct GoldenDigest: Sendable, Hashable {
        public let algorithmVersion: Int
        public let thresholdsVersion: Int
        public let contractVersion: Int
        /// SHA-256 over every file in `Tests/AMCoreTests/Golden/`, sorted by path, each as its path, a newline, its
        /// canonical JSON and a newline.
        public let digest: String
    }

    /// Append-only. To change a golden file: bump a version above, then append a record for the new triple with
    /// the new digest. Never edit an existing record.
    public static let goldenDigests: [GoldenDigest] = [
        GoldenDigest(
            algorithmVersion: 1, thresholdsVersion: 1, contractVersion: 1,
            digest: "542234344d63e3fbd511f831667be6f78a2477017d2a9ab4a7314467657d598a"),
        // Spec 05: `capture.endpointArmSpeechS` and `capture.noSpeechVoicedS` added (plan §10 values, not tuned).
        GoldenDigest(
            algorithmVersion: 1, thresholdsVersion: 2, contractVersion: 1,
            digest: "9c66917a2b02032b4788c048b02714e8425abe0e9aeb0f17d2bed8c08b1c443c"),
        // Spec 03: `wordTimestamps.medianErrorMaxMs`, `.withinToleranceMs`, `.withinToleranceShareMin` added (first v2
        // values, not tuned; evaluation gates only).
        GoldenDigest(
            algorithmVersion: 1, thresholdsVersion: 3, contractVersion: 1,
            digest: "0af7296e5a9c9d18ba8062b7176dcecd71a12f8dbd4fd08f5633b4bb8fda730a"),
        // Spec 07: span sanity and syllable-split confidence (`confidence.spanSanity*`, `.split*`) and the
        // `syllableBoundaries` bars added (first v2 values, not tuned).
        GoldenDigest(
            algorithmVersion: 1, thresholdsVersion: 4, contractVersion: 1,
            digest: "fce6552351e9076ad0daea2d2c1b02a6ec0dd547ad4611de73f52e3ec38fa351"),
        // Spec 10: `diffs.weakLengthEnabled`, `.pitchRangeEnabled`, `.finalDirectionEnabled` added (on; Open question
        // 1), and the scoring goldens under Golden/scoring/. Version 5 is held by spec 23 (#27).
        GoldenDigest(
            algorithmVersion: 1, thresholdsVersion: 6, contractVersion: 1,
            digest: "ba13dd10863932382111046991d0c2ec4a629904c7d5a395b7422789eaa9d8bf"),
    ]
}
