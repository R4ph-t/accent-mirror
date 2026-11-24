// The L1 syllable segmenter (spec 07, plan §9.2). Word boundaries are injected (`WordSpan`): spec 12 maps spec 03's
// timestamps, after spec 23's refiner, onto them; tests inject them directly. Nothing here imports ASR code.
//
// Per present word: the injected span is widened by `alignment.asrPaddingMs` (clamped at the neighbours' unpadded
// spans and the take's ends) to search for voiced energy nuclei; the word is then split into its dictionary
// syllables at intensity-envelope minima inside the unpadded span, or proportionally to phone count when the valleys
// can't give the dictionary count. Reported edges are the injected ones, never the padded ones, so a word's timing
// is the union of its syllables. No DTW here (first v2 §5).
//
// Spec 25: with `prominence.measurement == .nucleus` the spans above stay for display only, and each syllable's d, e
// and p come from its vowel nucleus (`NucleusDetector`, `NucleusAssigner`), which needs spec 04's pitch track. Exposure
// is structural in both modes: the last syllable of a phrase-final word or of a word before a pause.

import Accelerate
import AMAlignment
import AMCore
import AMPitch
import Foundation

public struct SyllableSegmenter: Sendable {
    /// One injected word boundary: start and end in seconds on the take's timeline, and the ASR word probability.
    public struct WordSpan: Sendable, Hashable, Codable {
        public let start: Double
        public let end: Double
        /// 0–1. TTS markers and other known boundaries are 1.
        public let probability: Double

        public enum Invalid: Error, Equatable { case notFinite, endBeforeStart, probabilityOutOfRange }

        public init(start: Double, end: Double, probability: Double) throws(Invalid) {
            guard start.isFinite, end.isFinite, probability.isFinite else { throw .notFinite }
            guard start <= end else { throw .endBeforeStart }
            guard (0...1).contains(probability) else { throw .probabilityOutOfRange }
            self.start = start
            self.end = end
            self.probability = probability
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            do {
                try self.init(
                    start: container.decode(Double.self, forKey: .start), end: container.decode(Double.self, forKey: .end),
                    probability: container.decode(Double.self, forKey: .probability))
            } catch let error as Invalid {
                throw DecodingError.dataCorruptedError(
                    forKey: .end, in: container, debugDescription: "Invalid WordSpan: \(error)")
            }
        }

        public var duration: Double { end - start }
    }

    /// Everything one segmentation reads.
    public struct Input: Sendable {
        /// Mono samples of the take.
        public var samples: [Float]
        public var sampleRate: Double
        public var alignment: WordAlignment
        /// The pronunciation used for each phrase word (spec 06); needed for every `present` word.
        public var pronunciations: [WordIndex: Pronunciation]
        /// One injected span per phrase word with audio (`present` and `substituted`).
        public var spans: [WordIndex: WordSpan]
        public var l0Key: String
        public var transcriptRevision: Int
        /// Spec 04's track of the take: its voicing finds the nuclei and its F0 gives p. Needed in `.nucleus` mode.
        public var pitch: PitchTrack?

        public init(
            samples: [Float], sampleRate: Double = 16_000, alignment: WordAlignment,
            pronunciations: [WordIndex: Pronunciation], spans: [WordIndex: WordSpan], l0Key: String,
            transcriptRevision: Int, pitch: PitchTrack? = nil
        ) {
            self.samples = samples
            self.sampleRate = sampleRate
            self.alignment = alignment
            self.pronunciations = pronunciations
            self.spans = spans
            self.l0Key = l0Key
            self.transcriptRevision = transcriptRevision
            self.pitch = pitch
        }
    }

    public enum Failure: Error, Equatable {
        case invalidSampleRate(Double)
        case missingSpan(WordIndex)
        case missingPronunciation(WordIndex)
        /// `.nucleus` mode needs the take's pitch track.
        case missingPitchTrack
    }

    /// The shortest syllable a valley split may produce. Algorithm constant, not a threshold: it only keeps a
    /// boundary off the word's edges and off another boundary.
    static let minimumSyllableS = 0.04
    /// A boundary candidate must dip at least this far below the envelope on both sides, so frame-level ripple on a
    /// steady vowel is not a valley. Algorithm constant: the 3 dB `splitValleyMinDB` decides the peak count, this
    /// only decides whether a minimum exists at all.
    static let minimumCandidateDepthDB = 0.5
    /// Envelope smoothing: a centred moving average over this many 10 ms frames.
    static let smoothingFrames = 5
    /// A peak counts as a voiced nucleus when a frame this close to it is voiced.
    static let voicedNeighbourhoodFrames = 2

    public let voicing: any VoicingSource
    public let thresholds: Thresholds

    public init(voicing: any VoicingSource, thresholds: Thresholds = .current) {
        self.voicing = voicing
        self.thresholds = thresholds
    }

    public func segment(_ input: Input) throws(Failure) -> SyllableSegmentation {
        guard input.sampleRate.isFinite, input.sampleRate > 0 else { throw .invalidSampleRate(input.sampleRate) }
        let measurement = thresholds.prominence.measurement
        if measurement == .nucleus && input.pitch == nil { throw .missingPitchTrack }
        let take = TakeSignal(samples: input.samples, sampleRate: input.sampleRate, voicing: voicing)

        // Every timed word on your timeline, for neighbours and pauses. Inserted words use their aligned range.
        var timed: [TimedWord] = []
        for pair in input.alignment.pairs {
            switch pair {
            case .present(let word, _), .substituted(let word, _, _):
                guard let span = input.spans[word] else { throw .missingSpan(word) }
                if case .present = pair, input.pronunciations[word] == nil { throw .missingPronunciation(word) }
                timed.append(TimedWord(start: span.start, end: span.end, word: word))
            case .inserted(_, let you, _):
                timed.append(TimedWord(start: you.start, end: you.end, word: nil))
            case .missing:
                continue
            }
        }
        timed.sort { ($0.start, $0.end) < ($1.start, $1.end) }

        var words: [SegmentedWord] = []
        for (position, item) in timed.enumerated() {
            guard let phraseWord = item.word, let span = input.spans[phraseWord] else { continue }
            let previous = position > 0 ? timed[position - 1] : nil
            let next = position + 1 < timed.count ? timed[position + 1] : nil
            let pronunciation = isPresent(phraseWord, in: input.alignment) ? input.pronunciations[phraseWord] : nil
            words.append(segmentWord(
                phraseWord, span: span, previous: previous, next: next, pronunciation: pronunciation, take: take))
        }

        var nuclei: [Nucleus]?
        if measurement == .nucleus, let pitch = input.pitch {
            let detected = NucleusDetector(thresholds: thresholds).detect(
                samples: input.samples, sampleRate: input.sampleRate, pitch: pitch)
            words = measureNuclei(words, nuclei: detected, take: take, pitch: pitch)
            nuclei = detected
        }
        words = markExposure(words, timed: timed)
        let timing = Self.timing(of: words.flatMap(\.syllables).map(\.level), thresholds: thresholds.confidence)
        let key = SyllableSegmentation.Key(
            l0Key: input.l0Key, transcriptRevision: input.transcriptRevision,
            pronunciationHash: Self.pronunciationHash(input.pronunciations))
        return SyllableSegmentation(
            key: key, words: words, timingShare: timing.share, timing: timing.level,
            measurement: measurement == .span ? nil : measurement, nuclei: nuclei)
    }

    /// SHA-256 of the canonical JSON of `[{word, arpabet}]`, sorted by word.
    public static func pronunciationHash(_ pronunciations: [WordIndex: Pronunciation]) -> String {
        struct Entry: Encodable {
            let word: Int
            let arpabet: String
        }
        let entries = pronunciations.sorted { $0.key < $1.key }.map { Entry(word: $0.key.rawValue, arpabet: $0.value.arpabet) }
        // Encoding plain ints and strings can't fail.
        return (try? CanonicalJSON.sha256(entries)) ?? ""
    }

    // MARK: Words

    private struct TimedWord {
        let start: Double
        let end: Double
        /// Nil for an inserted word.
        let word: WordIndex?
    }

    private func isPresent(_ word: WordIndex, in alignment: WordAlignment) -> Bool {
        alignment.pairs.contains { if case .present(word, _) = $0 { true } else { false } }
    }

    private func segmentWord(
        _ phraseWord: WordIndex, span: WordSpan, previous: TimedWord?, next: TimedWord?, pronunciation: Pronunciation?,
        take: TakeSignal
    ) -> SegmentedWord {
        let confidence = thresholds.confidence
        let overlaps = (previous.map { $0.end > span.start } ?? false) || (next.map { $0.start < span.end } ?? false)
        let durationMs = span.duration * 1000
        let sane = !overlaps && durationMs >= confidence.spanSanityMinMs && durationMs <= confidence.spanSanityMaxMs
        let spanSanity = sane ? 1.0 : confidence.spanSanityFailed
        let wordConfidence = min(span.probability, spanSanity)

        // Reported edges: the injected span, clamped to the take.
        let start = min(max(span.start, 0), take.duration)
        let end = min(max(span.end, start), take.duration)
        // Search window: padded, never crossing a neighbour's unpadded span or the take's ends, never narrower than
        // the span itself.
        let padding = thresholds.alignment.asrPaddingMs / 1000
        let windowStart = min(start, max(start - padding, previous?.end ?? 0, 0))
        let windowEnd = max(end, min(end + padding, next?.start ?? take.duration, take.duration))
        let window = Self.range(windowStart, windowEnd)

        guard let pronunciation, !pronunciation.syllables.isEmpty else {
            return SegmentedWord(
                phraseWord: phraseWord, kind: pronunciation == nil ? .substituted : .present,
                range: Self.range(start, end), injected: span, searchWindow: window, spanSanity: spanSanity,
                confidence: wordConfidence, split: nil, syllables: [])
        }

        let dictionary = pronunciation.syllables
        let peaks = take.nucleusCount(in: start...end, window: window, valleyMinDB: confidence.splitValleyMinDB)
        let split: SyllableSplit
        let boundaries: [Double]
        if let valleys = take.valleyBoundaries(in: start...end, count: dictionary.count - 1) {
            let mismatch = Double(abs(peaks - dictionary.count))
            split = SyllableSplit(
                method: .valleys, dictionaryCount: dictionary.count, peakCount: peaks,
                confidence: max(0, confidence.splitExact - confidence.splitPerMismatch * mismatch))
            boundaries = valleys
        } else {
            split = SyllableSplit(
                method: .proportional, dictionaryCount: dictionary.count, peakCount: peaks,
                confidence: confidence.splitFallback)
            boundaries = Self.proportionalBoundaries(start...end, phoneCounts: dictionary.map(\.phones.count))
        }

        let edges = [start] + boundaries + [end]
        let syllableConfidence = min(wordConfidence, split.confidence)
        let syllables = dictionary.enumerated().map { index, syllable in
            let range = Self.range(edges[index], edges[index + 1])
            return SegmentedSyllable(
                phraseWord: phraseWord, indexInWord: index, phones: syllable.phones, stress: syllable.stress,
                range: range, duration: range.duration,
                energyDBFS: max(take.rmsDBFS(in: range), thresholds.prominence.energyMinimumDBFS),
                lengtheningExposed: false, confidence: syllableConfidence,
                level: Self.level(of: syllableConfidence, thresholds: confidence))
        }
        return SegmentedWord(
            phraseWord: phraseWord, kind: .present, range: Self.range(start, end), injected: span, searchWindow: window,
            spanSanity: spanSanity, confidence: wordConfidence, split: split, syllables: syllables)
    }

    /// Boundaries splitting `span` in proportion to each syllable's phone count.
    static func proportionalBoundaries(_ span: ClosedRange<Double>, phoneCounts: [Int]) -> [Double] {
        let total = Double(phoneCounts.reduce(0, +))
        guard phoneCounts.count > 1, total > 0 else { return [] }
        let length = span.upperBound - span.lowerBound
        var sum = 0
        return phoneCounts.dropLast().map { count in
            sum += count
            return span.lowerBound + length * Double(sum) / total
        }
    }

    // MARK: Nuclei (spec 25 §2–§3)

    /// Replaces each present word's d, e and confidence with its nuclei's, or marks it nucleus-short. The spans
    /// (`range`) stay for display.
    private func measureNuclei(_ words: [SegmentedWord], nuclei: [Nucleus], take: TakeSignal, pitch: PitchTrack)
        -> [SegmentedWord]
    {
        // `words` are in your-time order; only present words with syllables take part. Substituted words get no
        // nuclei, so theirs are skipped.
        let present = words.indices.filter { words[$0].kind == .present && !words[$0].syllables.isEmpty }
        let assignment = NucleusAssigner.assign(
            nuclei.map(\.peakTime),
            to: present.map {
                NucleusAssigner.Word(
                    start: words[$0].injected.start, end: words[$0].injected.end, syllables: words[$0].syllables.count)
            },
            thresholds: thresholds)
        var out = words
        for (position, index) in present.enumerated() {
            let word = words[index]
            let result = assignment.words[position]
            let assigned = assignment.nuclei[position]
            let syllableConfidence = assigned == nil ? 0 : min(word.confidence, result.confidence)
            let syllables = word.syllables.enumerated().map { k, syllable in
                let measured = assigned.map {
                    NucleusMeasurement.measure($0[k], of: nuclei, take: take, pitch: pitch, thresholds: thresholds)
                }
                return SegmentedSyllable(
                    phraseWord: syllable.phraseWord, indexInWord: syllable.indexInWord, phones: syllable.phones,
                    stress: syllable.stress, range: syllable.range, duration: measured?.duration ?? syllable.duration,
                    energyDBFS: measured?.energyDBFS ?? syllable.energyDBFS,
                    lengtheningExposed: syllable.lengtheningExposed, confidence: syllableConfidence,
                    level: Self.level(of: syllableConfidence, thresholds: thresholds.confidence), nucleus: measured)
            }
            out[index] = word.with(syllables: syllables, nucleusAssignment: result)
        }
        return out
    }

    // MARK: Exposure (spec 25 §3, CTO markup 2)

    /// Structural, the same in `.span` and `.nucleus`: a syllable is exposed if it is the last syllable (by index) of
    /// a word that is phrase-final (nothing timed after it) or followed by a pause longer than
    /// `prominence.exposurePauseMs`, the pause being the gap from the word's end to the next timed word's start
    /// (present, substituted or inserted). No syllable or nucleus edge is read.
    private func markExposure(_ words: [SegmentedWord], timed: [TimedWord]) -> [SegmentedWord] {
        let pause = thresholds.prominence.exposurePauseMs / 1000
        return words.map { word in
            guard let position = timed.firstIndex(where: { $0.word == word.phraseWord }) else { return word }
            let next = timed[(position + 1)...].first
            let exposed = next.map { $0.start - word.range.end > pause } ?? true
            let last = word.syllables.count - 1
            return word.with(syllables: word.syllables.map { syllable in
                syllable.with(lengtheningExposed: exposed && syllable.indexInWord == last)
            })
        }
    }

    /// A `TimeRange` from values already ordered and finite.
    static func range(_ start: Double, _ end: Double) -> TimeRange {
        // Callers clamp `end >= start` and both are finite; fall back to an empty range at `start` otherwise.
        (try? TimeRange(start: start, end: max(start, end))) ?? (try! TimeRange(start: 0, end: 0))
    }
}

// MARK: - Signal

/// The take's intensity envelope and voicing on the shared 10 ms frame grid (frame `i` starts at `i × 10 ms`).
struct TakeSignal {
    let samples: [Float]
    let sampleRate: Double
    let duration: Double
    /// Smoothed frame RMS in dBFS.
    let envelope: [Double]
    let voiced: [Bool]

    init(samples: [Float], sampleRate: Double, voicing: any VoicingSource) {
        self.samples = samples
        self.sampleRate = sampleRate
        duration = Double(samples.count) / sampleRate
        let hop = max(1, Int((sampleRate * voicingFrameDuration).rounded()))
        let frameCount = (samples.count + hop - 1) / hop
        var raw = [Double](repeating: -120, count: frameCount)
        samples.withUnsafeBufferPointer { buffer in
            for frame in 0..<frameCount {
                let start = frame * hop
                let count = min(hop, samples.count - start)
                var rms: Float = 0
                vDSP_rmsqv(buffer.baseAddress! + start, 1, &rms, vDSP_Length(count))
                raw[frame] = 20 * log10(max(Double(rms), 1e-6))
            }
        }
        let half = SyllableSegmenter.smoothingFrames / 2
        envelope = raw.indices.map { index in
            let lower = max(0, index - half), upper = min(raw.count - 1, index + half)
            return raw[lower...upper].reduce(0, +) / Double(upper - lower + 1)
        }
        voiced = voicing.voicedFrames(samples: samples, sampleRate: sampleRate)
    }

    /// Frame centre time.
    func time(ofFrame frame: Int) -> Double { (Double(frame) + 0.5) * voicingFrameDuration }

    /// Frames whose centres fall inside `range`.
    func frames(in range: ClosedRange<Double>) -> ClosedRange<Int>? {
        let first = max(0, Int((range.lowerBound / voicingFrameDuration - 0.5).rounded(.up)))
        let last = min(envelope.count - 1, Int((range.upperBound / voicingFrameDuration - 0.5).rounded(.down)))
        return first <= last ? first...last : nil
    }

    func isVoiced(near frame: Int) -> Bool {
        let reach = SyllableSegmenter.voicedNeighbourhoodFrames
        let lower = max(0, frame - reach), upper = min(voiced.count - 1, frame + reach)
        return lower <= upper && voiced[lower...upper].contains(true)
    }

    func hasVoicedFrame(in range: ClosedRange<Double>) -> Bool {
        guard let frames = frames(in: range) else { return false }
        return frames.contains { $0 < voiced.count && voiced[$0] }
    }

    /// Voiced envelope peaks whose frames lie inside `span`, found as local maxima within the padded `window`, with
    /// neighbours separated by valleys shallower than `valleyMinDB` merged into one nucleus.
    func nucleusCount(in span: ClosedRange<Double>, window: TimeRange, valleyMinDB: Double) -> Int {
        guard let search = frames(in: window.start...window.end), let inside = frames(in: span),
            search.count >= 3
        else { return 0 }
        var peaks = (search.lowerBound + 1..<search.upperBound).filter { frame in
            inside.contains(frame) && envelope[frame] >= envelope[frame - 1] && envelope[frame] > envelope[frame + 1]
                && isVoiced(near: frame)
        }
        // Merge the pair with the shallowest valley until every valley is at least `valleyMinDB` deep.
        while peaks.count > 1 {
            let depths = zip(peaks, peaks.dropFirst()).map { left, right in
                min(envelope[left], envelope[right]) - envelope[left...right].min()!
            }
            guard let shallowest = depths.indices.min(by: { depths[$0] < depths[$1] }),
                depths[shallowest] < valleyMinDB
            else { break }
            let left = peaks[shallowest], right = peaks[shallowest + 1]
            peaks.remove(at: envelope[left] >= envelope[right] ? shallowest + 1 : shallowest)
        }
        return peaks.count
    }

    /// `count` boundaries at envelope minima strictly inside `span`, deepest first, each piece at least
    /// `minimumSyllableS` long and holding a voiced frame. Nil when that can't be done.
    func valleyBoundaries(in span: ClosedRange<Double>, count: Int) -> [Double]? {
        guard count > 0 else { return [] }
        guard let inside = frames(in: span), inside.count >= 3 else { return nil }
        let minimum = SyllableSegmenter.minimumSyllableS
        let candidates = (inside.lowerBound + 1..<inside.upperBound).compactMap { frame -> (time: Double, depth: Double)? in
            guard envelope[frame] <= envelope[frame - 1], envelope[frame] < envelope[frame + 1] else { return nil }
            let left = envelope[inside.lowerBound..<frame].max()!, right = envelope[(frame + 1)...inside.upperBound].max()!
            let depth = min(left, right) - envelope[frame]
            return depth >= SyllableSegmenter.minimumCandidateDepthDB ? (time(ofFrame: frame), depth) : nil
        }.sorted { $0.depth != $1.depth ? $0.depth > $1.depth : $0.time < $1.time }

        var chosen: [Double] = []
        for candidate in candidates where chosen.count < count {
            let trial = (chosen + [candidate.time]).sorted()
            let edges = [span.lowerBound] + trial + [span.upperBound]
            let valid = zip(edges, edges.dropFirst()).allSatisfy { start, end in
                end - start >= minimum && hasVoicedFrame(in: start...end)
            }
            if valid { chosen = trial }
        }
        return chosen.count == count ? chosen : nil
    }

    /// RMS over the samples of `range`, in dBFS; −∞ for an empty range.
    func rmsDBFS(in range: TimeRange) -> Double {
        let first = max(0, min(samples.count, Int((range.start * sampleRate).rounded())))
        let last = max(first, min(samples.count, Int((range.end * sampleRate).rounded())))
        guard last > first else { return -.infinity }
        var rms: Float = 0
        samples.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + first, 1, &rms, vDSP_Length(last - first)) }
        return rms > 0 ? 20 * log10(Double(rms)) : -.infinity
    }
}
