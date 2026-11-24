// The streaming endpointer (spec 05, plan §10): a value-type state machine fed one 10 ms frame at a time, so tests
// drive it without clocks or sleeps. Live capture (spec 14) feeds it; it never touches a microphone.

import AMCore
import Foundation

/// Decides when a take starts and ends, and which audio to keep.
///
/// - The take ends `endOfTakeS` after the last speech frame, once `endpointArmSpeechS` of speech has accumulated
///   (retracted onsets never count), or at `recordingCapS`, or at once on `stop()`. `cancel()` ends it with nothing.
/// - Kept audio starts at max(0, first kept `t_onset` − `preRollMs`). A take that ends with no kept onset keeps all
///   of its audio, so `TakeQuality` can still tell a quiet voiced take (`tooQuiet`) from silence (`noSpeech`).
public struct Endpointer: Sendable {
    public enum EndReason: String, Sendable, Hashable {
        /// `endOfTakeS` of non-speech after the last speech.
        case endOfSpeech
        /// The hard cap.
        case recordingCap
        /// The user stopped it.
        case manualStop
    }

    /// A finished take.
    public struct Take: Sendable, Hashable {
        public let reason: EndReason
        /// When the take ended, in seconds from the first frame.
        public let endTime: Double
        /// Where `audio` starts, in seconds from the first frame.
        public let audioStartTime: Double
        public let audio: [Float]
        /// Onsets that still count as speech, in order.
        public let onsets: [Onset]
        public let floorDBFS: Double
        /// The end of the last frame that still counts as speech, in seconds from the first frame; nil with no kept
        /// speech. For an `endOfSpeech` take it is `endTime − endOfTakeS`.
        public let lastSpeechEndTime: Double?
    }

    public enum State: Sendable, Hashable {
        case listening
        case ended(Take)
        /// Cancelled: no outcome, nothing kept.
        case cancelled
    }

    public enum Event: Sendable, Hashable {
        case onset(Onset)
        case floorSettled(dBFS: Double)
        case retracted(Onset)
        case ended(Take)
    }

    private let thresholds: Thresholds
    private let sampleRate: Double
    private var analyzer: FrameAnalyzer
    private var detector: SpeechDetector
    private let endFrames: Int
    private let armFrames: Int
    private let capFrames: Int
    private let preRollSamples: Int
    /// Every sample heard so far (bounded by the cap). Trimmed to the pre-roll when the take ends.
    private var audio: [Float] = []

    public private(set) var state: State = .listening

    public init(sampleRate: Double = 16_000, lastSessionFloorDBFS: Double? = nil, thresholds: Thresholds = .current) {
        self.thresholds = thresholds
        self.sampleRate = sampleRate
        analyzer = FrameAnalyzer(sampleRate: sampleRate, thresholds: thresholds)
        detector = SpeechDetector(lastSessionFloorDBFS: lastSessionFloorDBFS, thresholds: thresholds)
        let frameSeconds = detector.frameSeconds
        let capture = thresholds.capture
        endFrames = Int((capture.endOfTakeS / frameSeconds).rounded())
        armFrames = Int((capture.endpointArmSpeechS / frameSeconds).rounded())
        capFrames = Int((capture.recordingCapS / frameSeconds).rounded())
        // The pre-roll comes out of the ring buffer, so it can never reach further back than the buffer holds.
        preRollSamples = Int((min(capture.preRollMs, capture.ringBufferMs) / 1000 * sampleRate).rounded())
        audio.reserveCapacity(capFrames * analyzer.hop)
    }

    /// Samples per frame: `frame` passed to `process` must hold exactly this many.
    public var frameLength: Int { analyzer.hop }

    /// Seconds of audio processed so far.
    public var elapsed: Double { Double(detector.frameCount) * detector.frameSeconds }

    public var noiseFloorDBFS: Double { detector.floor.dBFS }
    public var isNoiseFloorSettled: Bool { detector.floor.isSettled }

    /// Samples held for the take right now (0 once it has ended or been cancelled).
    var bufferedSampleCount: Int { audio.count }

    /// Feeds the next 10 ms frame. Frames after the take has ended or been cancelled are ignored.
    public mutating func process(frame: [Float]) -> [Event] {
        guard state == .listening else { return [] }
        audio += frame
        var events: [Event] = []
        for event in detector.process(analyzer.analyse(frame)) {
            switch event {
            case .onset(let segment): events.append(.onset(detector.onset(of: detector.segments[segment])))
            case .floorSettled: events.append(.floorSettled(dBFS: detector.floor.dBFS))
            case .retracted(let segment): events.append(.retracted(detector.onset(of: detector.segments[segment])))
            }
        }

        let frames = detector.frameCount
        if detector.speechFrameCount >= armFrames, let last = detector.lastSpeechEnd, frames - last >= endFrames {
            events.append(.ended(end(.endOfSpeech)))
        } else if frames >= capFrames {
            events.append(.ended(end(.recordingCap)))
        }
        return events
    }

    /// Ends the take now, with no wait. Nil when it has already ended or been cancelled.
    public mutating func stop() -> Take? {
        guard state == .listening else { return nil }
        return end(.manualStop)
    }

    /// Ends the take with no outcome and drops everything heard.
    public mutating func cancel() {
        audio = []
        state = .cancelled
    }

    private mutating func end(_ reason: EndReason) -> Take {
        let kept = detector.segments.filter { !$0.retracted }
        let onsetSample = kept.first.map { Int((Double($0.start) * detector.frameSeconds * sampleRate).rounded()) }
        let startSample = onsetSample.map { max(0, $0 - preRollSamples) } ?? 0
        let take = Take(
            reason: reason, endTime: elapsed, audioStartTime: Double(startSample) / sampleRate,
            audio: Array(audio[min(startSample, audio.count)...]), onsets: kept.map(detector.onset(of:)),
            floorDBFS: detector.floor.dBFS,
            lastSpeechEndTime: detector.lastSpeechEnd.map { Double($0) * detector.frameSeconds })
        audio = []
        state = .ended(take)
        return take
    }
}
