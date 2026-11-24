// Descriptive measures (spec 28 §4a): one function, run on every speaker over the same kind of frames, so your values
// and the native range are comparable by eye. No comparison is made here.
//
// Frames (recorded in spec 28's Implementation notes):
// - pitch range: each speaker's pitch warped onto the selected model's timeline (`TimeWarp.pitchOnModel`), voiced
//   frames whose centre is in that warp's comparable model time: exactly the frames spec 10 reads for your range;
//   the selected voice goes through its own (identity) warp;
// - final slope: the speaker's final window on their own timeline over their present words (`FinalWindow`), as
//   spec 10 reads it for both you and the model;
// - length, syllables per second and nPVI: the speaker's present words and comparable syllables on their own timeline
//   (durations are a speaker's own; nPVI is spec 10's rhythm over the same syllables).

import AMCore
import AMPitch
import AMProsody
import AMWarp
import Foundation

public enum ProsodyDescription {
    /// One speaker's measures. `warp` maps this speaker onto the selected model (identity for the model itself).
    public static func speaker(_ take: TakeProsody, warp: TimeWarp, thresholds: Thresholds = .current) -> SpeakerDescription {
        let present = take.segmentation.words.filter { $0.kind == .present }
        let syllables = ComparableSyllable.all(in: take.segmentation, pitch: take.pitch, thresholds: thresholds.prominence)
        let length: Double? = present.isEmpty ? nil
            : max(0, (present.map(\.range.end).max() ?? 0) - (present.map(\.range.start).min() ?? 0))

        let hop = take.pitch.hopSeconds
        var onModel: [Double] = []
        for segment in warp.pitchOnModel(take.pitch.segments, hopSeconds: hop) {
            let k0 = Int((segment.start / hop).rounded())
            for (j, frame) in segment.frames.enumerated() where frame.voiced {
                if warp.isComparable(modelTime: (Double(k0 + j) + 0.5) * hop) { onModel.append(frame.semitones) }
            }
        }
        let window = FinalWindow(
            pitch: take.pitch.segments, material: present.map(\.range), hopSeconds: hop,
            thresholds: thresholds.finalDirection)

        let lengthValue: DescribedValue = length.map { .value($0) } ?? .missing(.noWords)
        let rate: DescribedValue =
            if let length, length > 0 { .value(Double(syllables.count) / length) } else { .missing(.noWords) }
        let range: DescribedValue =
            PitchStatistics.range(onModel, thresholds: thresholds.band).map { .value($0) } ?? .missing(.noVoicedFrames)
        let npvi: DescribedValue =
            PitchStatistics.npvi(syllables.map(\.features.duration)).map { .value($0) } ?? .missing(.tooFewSyllables)
        let slope: DescribedValue =
            window.slope.map { .value($0) } ?? .missing(window.voicedFrames == 0 ? .noVoicedFrames : .tooFewFinalFrames)
        return SpeakerDescription(
            lengthSeconds: lengthValue, syllablesPerSecond: rate, pitchRangeSemitones: range, rhythmNPVI: npvi,
            finalSlope: slope,
            endingDirection: window.slope.map { PitchDirection(slope: $0, thresholds: thresholds.finalDirection) })
    }

    /// You, and the range over `natives` (each with its warp onto the selected model).
    public static func describe(
        you: TakeProsody, yourWarp: TimeWarp, natives: [(prosody: TakeProsody, warp: TimeWarp)],
        thresholds: Thresholds = .current
    ) -> DescribedMeasures {
        DescribedMeasures(
            you: speaker(you, warp: yourWarp, thresholds: thresholds),
            native: NativeDescription(natives.map { speaker($0.prosody, warp: $0.warp, thresholds: thresholds) }))
    }
}
