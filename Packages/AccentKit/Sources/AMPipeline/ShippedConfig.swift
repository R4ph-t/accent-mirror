// What the shipped analysis runs. Spec 23 measured word-boundary refiners; per the CTO ruling of 2026-11-24 on #27
// they are measurement-only and the app keeps Whisper's word timings unrefined. b2 (`ctc-w2v2b960-1`) lives in a
// tooling-only target that nothing in this module's closure depends on (ShippedAlignerTests).

import AMAlignment
import AMCore
import AMCapture
import AMPitch

public enum ShippedConfig {
    /// The word-boundary refiner the shipped analysis runs after ASR: none, Whisper's timings as recognised.
    public static let wordBoundaryRefiner: any WordBoundaryRefiner = WhisperOnly()

    /// The configuration identity of a shipped analysis whose word timings came from `asrModelID`.
    public static func identity(asrModelID: String) -> ConfigIdentity {
        ConfigIdentity(
            asrModelID: asrModelID, pitchTrackerID: PYINTracker.trackerID, voicingID: ACFVoicing.voicingID,
            aligner: wordBoundaryRefiner.id, alignerModelSHA256: "none")
    }
}
