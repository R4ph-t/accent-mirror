// The word-boundary seam (spec 23): after ASR and before syllable segmentation, a refiner may move each word's start
// and end closer to where the word really starts and ends. `WhisperOnly` is the baseline and the fallback; a new
// refiner is a new type with a new `id`, recorded as `ConfigIdentity.aligner`.

import Foundation

/// Moves Whisper word boundaries, on device.
///
/// A refiner keeps word order, text and probabilities, and moves only `start` and `end`: never earlier than the
/// previous word's refined end, never later than the next word's refined start, and never outside the take. It
/// checks `Task.isCancelled` at least every 50 ms of work and throws `CancellationError` with no partial result.
public protocol WordBoundaryRefiner: Sendable {
    /// The `aligner` recorded in `ConfigIdentity` (`whisper`, `dsp-snap-1`, `ctc-w2v2b960-1`).
    var id: String { get }

    /// The words with refined boundaries. `samples` is the take, mono, at `sampleRate` Hz, on the words' timeline.
    func refine(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> [WordTimestamp]
}

/// No refinement: the words exactly as the recogniser timed them.
public struct WhisperOnly: WordBoundaryRefiner {
    public static let aligner = "whisper"

    public var id: String { Self.aligner }

    public init() {}

    public func refine(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> [WordTimestamp] {
        try Task.checkCancellation()
        return words
    }
}

/// The search every refiner shares: each boundary is looked for within `window` seconds of where the recogniser put
/// it, word by word from the left, with the clamps of `WordBoundaryRefiner` applied by construction.
public enum BoundarySearch {
    /// Where one boundary may move: the recogniser's time and the clamped search interval, in seconds.
    public struct Window: Sendable, Equatable {
        public var original: Double
        public var lower: Double
        public var upper: Double
    }

    /// Refines `words` in order. `findStart` and `findEnd` get the word's index and its window and return a boundary
    /// inside the window, or nil when they find none; nil keeps the recogniser's time (clamped). Each word's start
    /// window lies between the previous word's refined end and its own recognised end; its end window between its
    /// refined start and the next word's recognised end, so the next start can always follow it. Everything stays inside `[0, takeDuration]`.
    public static func refine(
        _ words: [WordTimestamp], takeDuration: Double, windowSeconds: Double,
        findStart: (Int, Window) throws -> Double?, findEnd: (Int, Window) throws -> Double?
    ) throws -> [WordTimestamp] {
        let duration = max(takeDuration, 0)
        var refined: [WordTimestamp] = []
        refined.reserveCapacity(words.count)
        var previousEnd = 0.0
        for (index, word) in words.enumerated() {
            try Task.checkCancellation()
            let startLower = min(max(previousEnd, word.start - windowSeconds), duration)
            let startUpper = max(startLower, min(word.start + windowSeconds, word.end, duration))
            let startWindow = Window(original: word.start, lower: startLower, upper: startUpper)
            let start = clamp(try findStart(index, startWindow) ?? word.start, startWindow)

            let nextEnd = index + 1 < words.count ? words[index + 1].end : duration
            let endLower = max(start, word.end - windowSeconds)
            let endUpper = max(endLower, min(word.end + windowSeconds, nextEnd, duration))
            let endWindow = Window(original: word.end, lower: endLower, upper: endUpper)
            let end = clamp(try findEnd(index, endWindow) ?? word.end, endWindow)

            var moved = word
            moved.start = start
            moved.end = end
            refined.append(moved)
            previousEnd = end
        }
        return refined
    }

    static func clamp(_ time: Double, _ window: Window) -> Double {
        min(max(time, window.lower), window.upper)
    }
}
