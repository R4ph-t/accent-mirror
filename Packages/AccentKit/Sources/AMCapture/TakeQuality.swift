// Take quality (spec 05, plan §10; v1 rows): one batch pass of the speech detector over a take, and the first
// problem in Designer's order.

import AMCore
import Foundation

/// One pass of the endpointer's detector over a whole take, with no endpoint and no cap.
public struct TakeAnalysis: Sendable {
    /// Onsets that still count as speech (provisional onsets the settled floor retracted are left out).
    public let onsets: [Onset]
    /// Seconds of frames inside kept speech segments.
    public let speechSeconds: Double
    /// Seconds of voiced frames, judged against the floor as finally known.
    public let voicedSeconds: Double
    /// Median frame RMS of the kept speech frames, or nil when there are none.
    public let speechMedianDBFS: Double?
    /// Share of kept speech frames holding a clip run (0 when there is no speech).
    public let clippedShare: Double
    /// The floor at the end of the take, and whether it settled.
    public let floorDBFS: Double
    public let floorSettled: Bool
    /// One voicing decision per 10 ms frame.
    public let voiced: [Bool]
    /// The kept speech segments, `[start, end)` in seconds from the start of the take (spec 17's importer shows them).
    public let speechRegions: [Range<Double>]
    private let capture: Thresholds.Capture

    public init(
        samples: [Float], sampleRate: Double = 16_000, lastSessionFloorDBFS: Double? = nil,
        thresholds: Thresholds = .current
    ) {
        var analyzer = FrameAnalyzer(sampleRate: sampleRate, thresholds: thresholds)
        var detector = SpeechDetector(lastSessionFloorDBFS: lastSessionFloorDBFS, thresholds: thresholds)
        capture = thresholds.capture
        var start = 0
        while start < samples.count {
            var frame = Array(samples[start..<min(start + analyzer.hop, samples.count)])
            if frame.count < analyzer.hop { frame += [Float](repeating: 0, count: analyzer.hop - frame.count) }
            _ = detector.process(analyzer.analyse(frame))
            start += analyzer.hop
        }

        let kept = detector.segments.filter { !$0.retracted }
        let speechFrames = kept.flatMap { detector.features[$0.start..<$0.end] }
        onsets = kept.map(detector.onset(of:))
        speechRegions = kept.map { Double($0.start) * detector.frameSeconds..<Double($0.end) * detector.frameSeconds }
        speechSeconds = Double(speechFrames.count) * detector.frameSeconds
        voiced = detector.voicedFrames
        voicedSeconds = Double(voiced.filter { $0 }.count) * detector.frameSeconds
        speechMedianDBFS = speechFrames.isEmpty ? nil : percentile(50, of: speechFrames.map(\.rmsDBFS))
        clippedShare =
            speechFrames.isEmpty ? 0 : Double(speechFrames.filter(\.clipped).count) / Double(speechFrames.count)
        floorDBFS = detector.floor.dBFS
        floorSettled = detector.floor.isSettled
    }

    /// Every take problem this pass finds (`noMicrophone`, `micDenied` and `wordsDontMatch` come from elsewhere).
    ///
    /// - `noSpeech`: under `noSpeechS` of detected speech and under `noSpeechVoicedS` of voiced frames.
    /// - `tooQuiet` by the voiced rule: under `noSpeechS` of detected speech but at least `noSpeechVoicedS` voiced.
    ///   Such a take is not also `tooShort`: nothing crossed detection, so its length was never measured.
    /// - Otherwise `tooShort` under `tooShortS`, `tooQuiet` when the speech median is below `tooQuietDBFS`, and
    ///   `clipped` at or above `clippedShare` of speech frames with a clip run.
    public var problems: [TakeProblem] {
        guard speechSeconds >= capture.noSpeechS - 1e-9 else {
            return voicedSeconds >= capture.noSpeechVoicedS - 1e-9 ? [.tooQuiet] : [.noSpeech]
        }
        var problems: [TakeProblem] = []
        if speechSeconds < capture.tooShortS - 1e-9 { problems.append(.tooShort) }
        if let speechMedianDBFS, speechMedianDBFS < capture.tooQuietDBFS { problems.append(.tooQuiet) }
        if clippedShare >= capture.clippedShare { problems.append(.clipped) }
        return problems
    }

    /// The first problem in Designer's order, or nil.
    public var problem: TakeProblem? { TakeProblem.first(of: problems) }
}

/// The user-correctable problems a take's audio shows on its own.
public enum TakeQuality {
    /// The first problem in Designer's order, or nil when the take is fine. `samples` are mono Float32.
    public static func check(
        samples: [Float], sampleRate: Double = 16_000, lastSessionFloorDBFS: Double? = nil,
        thresholds: Thresholds = .current
    ) -> TakeProblem? {
        TakeAnalysis(
            samples: samples, sampleRate: sampleRate, lastSessionFloorDBFS: lastSessionFloorDBFS,
            thresholds: thresholds
        ).problem
    }
}
