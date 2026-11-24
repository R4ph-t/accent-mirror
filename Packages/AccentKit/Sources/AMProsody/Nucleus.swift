// Nucleus-anchored syllable measurement (spec 25, spec 11 §4c's FALLBACK). Each syllable's stress features come from
// a window around its vowel nucleus, found once per take from the band-limited energy envelope and spec 04's voicing,
// before and independent of any word boundary. Word spans only decide which nucleus belongs to which word, through a
// monotonic assignment where an edge is a soft anchor (a cost in ms), so moving an edge changes nothing unless a peak
// sits close to it.
//
// - `NucleusDetector`: samples + spec 04's pitch track → `[Nucleus]` (§1). Reads no word boundary.
// - `NucleusAssigner`: nuclei + the present words' spans and dictionary syllable counts → per word its nuclei, P and
//   s_w, or nucleus-short (§2).
// - `NucleusMeasurement`: per syllable, d (region length), e (±`windowMs` around the peak) and p (§3).

import Accelerate
import AMCore
import AMPitch
import Foundation

/// One vowel nucleus of a take. Times are seconds on the take's timeline; frames are spec 04's 10 ms cells.
public struct Nucleus: Sendable, Hashable, Codable {
    /// Centre of the peak frame.
    public let peakTime: Double
    /// The smoothed band-limited envelope at the peak, dBFS.
    public let peakDB: Double
    /// dB above the higher of the two minima separating the peak from its neighbouring nuclei (or the take's ends).
    public let prominenceDB: Double
    /// Centre of the envelope minimum between this nucleus and the previous one (or the take's start).
    public let leftValleyTime: Double
    /// Centre of the envelope minimum between this nucleus and the next one (or the take's end).
    public let rightValleyTime: Double
    /// The contiguous voiced frames holding the peak.
    public let voicedRun: TimeRange
    /// The nucleus region (§1): contiguous voiced frames within `regionDropDB` of the peak, inside the valleys.
    public let region: TimeRange

    public init(peakTime: Double, peakDB: Double, prominenceDB: Double, leftValleyTime: Double, rightValleyTime: Double,
                voicedRun: TimeRange, region: TimeRange) {
        self.peakTime = peakTime
        self.peakDB = peakDB
        self.prominenceDB = prominenceDB
        self.leftValleyTime = leftValleyTime
        self.rightValleyTime = rightValleyTime
        self.voicedRun = voicedRun
        self.region = region
    }
}

/// One syllable's stress features from its nucleus (§3).
public struct NucleusMeasurement: Sendable, Hashable, Codable {
    /// Index of the nucleus in the take's detected nuclei.
    public let nucleusIndex: Int
    public let peakTime: Double
    /// The nucleus region: d is its length, p is read over its voiced frames.
    public let region: TimeRange
    /// d, seconds: the region's length.
    public let duration: Double
    /// e: full-band RMS over ± `nucleus.windowMs` around the peak, clamped to the region, floored at
    /// `prominence.energyMinimumDBFS`.
    public let energyDBFS: Double
    /// p: peak F0 in st re the speaker's median over the region's voiced frames; nil with fewer than
    /// `prominence.pitchMinVoicedFrames`.
    public let peakSemitones: Double?

    public init(nucleusIndex: Int, peakTime: Double, region: TimeRange, duration: Double, energyDBFS: Double,
                peakSemitones: Double?) {
        self.nucleusIndex = nucleusIndex
        self.peakTime = peakTime
        self.region = region
        self.duration = duration
        self.energyDBFS = energyDBFS
        self.peakSemitones = peakSemitones
    }
}

/// One present word's nucleus assignment (§2).
public struct NucleusWordAssignment: Sendable, Hashable, Codable {
    /// P: the nuclei between the previous word's last assigned nucleus and the next word's first (exclusive), i.e. the
    /// nuclei the word could take (CTO markup 1).
    public let available: Int
    /// The dictionary syllable count N_w.
    public let dictionaryCount: Int
    /// Fewer than N_w nuclei could be assigned: no stress features, placement and contrast unavailable.
    public let short: Bool
    /// s_w: `splitExact` − `splitPerMismatch` · |P − N|, floored at 0, N the allowed count closest to P (spec 07's
    /// rule; spec 26 §2).
    public let confidence: Double
    /// Spec 26 §2: N_w as a set (context count, CMUdict alternates, reduced forms); nil when it is the context count
    /// alone.
    public let allowed: [Int]?
    /// Spec 26 §2: the count the assignment gave the word, when it isn't the context count.
    public let assignedCount: Int?
    /// Spec 26 §3: the word's verdict differs between the two candidate assignments of a peak near its edge.
    public let ambiguous: Bool?

    public init(available: Int, dictionaryCount: Int, short: Bool, confidence: Double, allowed: [Int]? = nil,
                assignedCount: Int? = nil, ambiguous: Bool? = nil) {
        self.available = available
        self.dictionaryCount = dictionaryCount
        self.short = short
        self.confidence = confidence
        self.allowed = allowed
        self.assignedCount = assignedCount
        self.ambiguous = ambiguous
    }

    func with(ambiguous: Bool) -> NucleusWordAssignment {
        NucleusWordAssignment(available: available, dictionaryCount: dictionaryCount, short: short,
                              confidence: confidence, allowed: allowed, assignedCount: assignedCount,
                              ambiguous: ambiguous ? true : nil)
    }
}

// MARK: - Detection (§1)

public struct NucleusDetector: Sendable {
    /// Band of the energy envelope (the vowel formant region). Spec 25 §1, not a tunable.
    static let bandHz: ClosedRange<Double> = 300...2_500
    /// Envelope analysis window, centred on each 10 ms cell (spec 04's frames).
    static let windowSeconds = 0.025
    /// The 50 ms zero-phase moving average: a centred mean over this many 10 ms frames.
    static let smoothingFrames = 5
    /// Level of a silent frame, so log stays finite. Numerical guard.
    static let silentDBFS = -120.0

    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .current) {
        self.thresholds = thresholds
    }

    /// The take's nuclei in time order. Reads the samples and the pitch track's voicing only.
    public func detect(samples: [Float], sampleRate: Double, pitch: PitchTrack) -> [Nucleus] {
        let envelope = Self.envelope(samples: samples, sampleRate: sampleRate)
        let voiced = Self.voicedCells(pitch, count: envelope.count)
        return detect(envelope: envelope, voiced: voiced)
    }

    /// Detection on a precomputed smoothed envelope (dBFS per 10 ms cell) and per-cell voicing.
    public func detect(envelope: [Double], voiced: [Bool]) -> [Nucleus] {
        let settings = thresholds.nucleus
        let count = envelope.count
        guard count >= 3 else { return [] }
        func isVoiced(_ frame: Int) -> Bool { frame >= 0 && frame < voiced.count && voiced[frame] }
        // Spec 26 §1: a peak is voiced when a voiced cell's centre lies within ± `voicedWithinMs` of the peak cell's
        // centre (0: the peak cell itself, spec 25's rule).
        let reach = Int((settings.voicedWithinMs / (voicingFrameDuration * 1000) + 1e-9).rounded(.down))
        func nearestVoiced(_ frame: Int, lower: Int = Int.min, upper: Int = Int.max) -> Int? {
            if isVoiced(frame) { return frame }
            guard reach > 0 else { return nil }
            for distance in 1...reach {
                // pYIN's voicing lags the vowel onset (spec 26 §1a), so on a tie the later cell wins.
                if frame + distance < upper && isVoiced(frame + distance) { return frame + distance }
                if frame - distance > lower && isVoiced(frame - distance) { return frame - distance }
            }
            return nil
        }

        // Candidates: voiced local maxima at or above the level floor.
        var peaks = (1..<(count - 1)).filter { frame in
            envelope[frame] >= envelope[frame - 1] && envelope[frame] > envelope[frame + 1]
                && nearestVoiced(frame) != nil && envelope[frame] >= settings.minPeakDBFS
        }
        let separation = settings.minSeparationMs / 1000

        func valley(_ lower: Int, _ upper: Int) -> Int {
            // The first minimum in [lower, upper].
            var best = lower
            for frame in lower...upper where envelope[frame] < envelope[best] { best = frame }
            return best
        }
        func prominences(_ peaks: [Int]) -> [Double] {
            peaks.indices.map { index in
                let left = valley(index > 0 ? peaks[index - 1] : 0, peaks[index])
                let right = valley(peaks[index], index + 1 < peaks.count ? peaks[index + 1] : count - 1)
                return envelope[peaks[index]] - max(envelope[left], envelope[right])
            }
        }

        // Merge until stable: first any pair closer than the minimum separation (keep the higher; the earlier on a
        // tie), then the least prominent candidate under the minimum prominence (the lower, then the later, on a tie).
        while true {
            if let close = zip(peaks, peaks.dropFirst()).enumerated()
                .filter({ Self.time(ofFrame: $0.element.1) - Self.time(ofFrame: $0.element.0) < separation - 1e-9 })
                .min(by: { ($0.element.1 - $0.element.0, $0.offset) < ($1.element.1 - $1.element.0, $1.offset) })
            {
                let (left, right) = close.element
                peaks.remove(at: envelope[left] >= envelope[right] ? close.offset + 1 : close.offset)
                continue
            }
            let prominence = prominences(peaks)
            guard let weakest = prominence.indices.filter({ prominence[$0] < settings.minProminenceDB }).min(by: {
                (prominence[$0], envelope[peaks[$0]], -$0) < (prominence[$1], envelope[peaks[$1]], -$1)
            }) else { break }
            peaks.remove(at: weakest)
        }

        let prominence = prominences(peaks)
        return peaks.indices.map { index in
            let peak = peaks[index]
            let leftValley = valley(index > 0 ? peaks[index - 1] : 0, peak)
            let rightValley = valley(peak, index + 1 < peaks.count ? peaks[index + 1] : count - 1)
            // The region grows from the voiced cell nearest the peak (the peak itself when it is voiced), inside the
            // valleys; with no voiced cell there it is the peak cell alone.
            let anchor = nearestVoiced(peak, lower: leftValley, upper: rightValley) ?? peak
            var runStart = anchor, runEnd = anchor
            while runStart > 0 && isVoiced(runStart - 1) { runStart -= 1 }
            while runEnd + 1 < count && isVoiced(runEnd + 1) { runEnd += 1 }
            // The region: voiced, within `regionDropDB` of the peak, never reaching a valley to a neighbour.
            let floor = envelope[peak] - settings.regionDropDB
            var first = anchor, last = anchor
            if isVoiced(anchor) {
                while first - 1 > leftValley && isVoiced(first - 1) && envelope[first - 1] >= floor { first -= 1 }
                while last + 1 < rightValley && isVoiced(last + 1) && envelope[last + 1] >= floor { last += 1 }
            }
            return Nucleus(
                peakTime: Self.time(ofFrame: peak), peakDB: envelope[peak], prominenceDB: prominence[index],
                leftValleyTime: Self.time(ofFrame: leftValley), rightValleyTime: Self.time(ofFrame: rightValley),
                voicedRun: Self.cells(runStart, runEnd), region: Self.cells(first, last))
        }
    }

    /// Centre of 10 ms cell `frame`.
    static func time(ofFrame frame: Int) -> Double { (Double(frame) + 0.5) * voicingFrameDuration }

    /// The time range covering cells `first...last`.
    static func cells(_ first: Int, _ last: Int) -> TimeRange {
        SyllableSegmenter.range(Double(first) * voicingFrameDuration, Double(last + 1) * voicingFrameDuration)
    }

    /// Per 10 ms cell from the take's start: voiced in the track (bridged frames are not).
    public static func voicedCells(_ pitch: PitchTrack, count: Int) -> [Bool] {
        var cells = [Bool](repeating: false, count: count)
        let hop = pitch.hopSeconds
        for segment in pitch.segments {
            let first = Int((segment.start / hop).rounded())
            for (k, frame) in segment.frames.enumerated() where frame.voiced {
                let cell = first + k
                if cell >= 0 && cell < count { cells[cell] = true }
            }
        }
        return cells
    }

    /// The smoothed band-limited envelope (§1): per 10 ms cell, the RMS of the 300–2,500 Hz band over a 25 ms Hann
    /// window centred on the cell, in dBFS, then a centred 5-frame (50 ms) moving average.
    public static func envelope(samples: [Float], sampleRate: Double) -> [Double] {
        let hop = max(1, Int((sampleRate * voicingFrameDuration).rounded()))
        let frameCount = (samples.count + hop - 1) / hop
        guard frameCount > 0 else { return [] }
        let window = max(2, Int((sampleRate * windowSeconds).rounded()))
        var log2n = 1
        while (1 << log2n) < window { log2n += 1 }
        let size = 1 << log2n
        let half = size / 2
        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        let hann = (0..<window).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(window - 1)) }
        let windowPower = Double(hann.reduce(0) { $0 + $1 * $1 })
        let lowBin = Int((bandHz.lowerBound * Double(size) / sampleRate).rounded(.up))
        let highBin = min(half - 1, Int((bandHz.upperBound * Double(size) / sampleRate).rounded(.down)))

        var frame = [Float](repeating: 0, count: size)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var raw = [Double](repeating: silentDBFS, count: frameCount)
        for index in 0..<frameCount {
            let centre = index * hop + hop / 2
            let start = centre - window / 2
            for k in 0..<size { frame[k] = 0 }
            for k in 0..<window {
                let sample = start + k
                if sample >= 0 && sample < samples.count { frame[k] = samples[sample] * hann[k] }
            }
            var power = 0.0
            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                    frame.withUnsafeBufferPointer { input in
                        input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
                    // zrip returns twice the DFT. Bins 1..<half are the positive frequencies.
                    if lowBin <= highBin {
                        for bin in max(1, lowBin)...highBin {
                            let re = Double(realBuffer[bin]) / 2, im = Double(imaginaryBuffer[bin]) / 2
                            power += re * re + im * im
                        }
                    }
                }
            }
            // Parseval with the window's power: both sides of the spectrum, over N · Σw².
            let meanSquare = 2 * power / (Double(size) * windowPower)
            raw[index] = meanSquare > 0 ? max(10 * log10(meanSquare), silentDBFS) : silentDBFS
        }
        let reach = smoothingFrames / 2
        return raw.indices.map { index in
            let lower = max(0, index - reach), upper = min(raw.count - 1, index + reach)
            return raw[lower...upper].reduce(0, +) / Double(upper - lower + 1)
        }
    }
}

// MARK: - Assignment (§2)

public enum NucleusAssigner {
    /// One present word, in time order.
    public struct Word: Sendable, Hashable {
        /// The unpadded injected span.
        public let start: Double
        public let end: Double
        /// The context pronunciation's syllable count.
        public let syllables: Int
        /// Spec 26 §2: N_w, the allowed counts (sorted, holding `syllables`).
        public let allowed: [Int]

        public init(start: Double, end: Double, syllables: Int, allowed: [Int]? = nil) {
            self.start = start
            self.end = end
            self.syllables = syllables
            self.allowed = Array(Set((allowed ?? []) + [syllables])).filter { $0 > 0 }.sorted()
        }

        /// The ms by which `time` lies outside the span (0 inside).
        func outsideMs(_ time: Double) -> Double { max(0, start - time, time - end) * 1000 }
    }

    public struct Result: Sendable, Hashable {
        /// Per word, the indices of its assigned nuclei in order (a count in N_w), or nil when nucleus-short.
        public let nuclei: [[Int]?]
        /// Per word, its assignment (P, short, s_w).
        public let words: [NucleusWordAssignment]
    }

    /// The monotonic assignment: each word gets a count in N_w of consecutive nuclei or is marked short. Cost of a
    /// nucleus in a word: how far (ms) its peak lies outside the word's unpadded span; a nucleus further than
    /// `alignment.asrPaddingMs` outside can't be assigned to that word. Skipping a nucleus costs `nucleus.skipCostMs`.
    /// The program minimises the number of short words first, then the cost, then the number of words given a count
    /// other than their context count (spec 26 §2: ties go to the context count); remaining ties go to the earlier
    /// word.
    public static func assign(_ nuclei: [Double], to words: [Word], thresholds: Thresholds = .current) -> Result {
        let n = nuclei.count, m = words.count
        let skip = thresholds.nucleus.skipCostMs
        let padding = thresholds.alignment.asrPaddingMs

        /// The cost of word j taking nuclei i..<i+count; nil when one is out of reach or there are too few.
        func take(_ i: Int, _ j: Int, _ count: Int) -> Cost? {
            guard count > 0, i + count <= n else { return nil }
            var total = 0.0
            for k in i..<(i + count) {
                let outside = words[j].outsideMs(nuclei[k])
                guard outside <= padding + Cost.tolerance else { return nil }
                total += outside
            }
            return Cost(short: 0, ms: total, alternate: count == words[j].syllables ? 0 : 1)
        }
        /// Context count first, then the others ascending: the forward pass prefers them in this order.
        func counts(_ j: Int) -> [Int] { [words[j].syllables] + words[j].allowed.filter { $0 != words[j].syllables } }

        // best[i][j]: least cost to finish from nucleus i, word j.
        var best = Array(repeating: Array(repeating: Cost(short: Int.max / 4, ms: 0, alternate: 0), count: m + 1),
                         count: n + 1)
        for i in stride(from: n, through: 0, by: -1) {
            for j in stride(from: m, through: 0, by: -1) {
                if i == n && j == m { best[i][j] = Cost(short: 0, ms: 0, alternate: 0); continue }
                var options: [Cost] = []
                if j < m {
                    for count in counts(j) {
                        if let c = take(i, j, count) { options.append(c + best[i + count][j + 1]) }
                    }
                }
                if i < n { options.append(Cost(short: 0, ms: skip, alternate: 0) + best[i + 1][j]) }
                if j < m { options.append(Cost(short: 1, ms: 0, alternate: 0) + best[i][j + 1]) }
                best[i][j] = options.min()!
            }
        }

        // Forward: at each state prefer giving the word its nuclei now (context count first), then skipping a
        // nucleus, then short. Taking now gives a contested nucleus to the earlier word.
        var assigned = [[Int]?](repeating: nil, count: m)
        var i = 0, j = 0
        while i < n || j < m {
            let target = best[i][j]
            if j < m, let count = counts(j).first(where: { count in
                take(i, j, count).map { $0 + best[i + count][j + 1] == target } ?? false
            }) {
                assigned[j] = Array(i..<(i + count))
                i += count
                j += 1
            } else if i < n, Cost(short: 0, ms: skip, alternate: 0) + best[i + 1][j] == target {
                i += 1
            } else {
                j += 1
            }
        }
        return Result(nuclei: assigned, words: results(assigned, words: words, nucleusCount: n, thresholds: thresholds))
    }

    /// P, short and s_w of every word under an assignment (CTO markup 1): P counts the nuclei strictly between the
    /// nearest earlier and later words' assigned nuclei; s_w reads |P − N| with N the allowed count closest to P.
    static func results(_ assigned: [[Int]?], words: [Word], nucleusCount n: Int, thresholds: Thresholds)
        -> [NucleusWordAssignment]
    {
        let confidence = thresholds.confidence
        return words.indices.map { j -> NucleusWordAssignment in
            let previous = assigned[..<j].last { $0?.isEmpty == false }??.last ?? -1
            let next = assigned[(j + 1)...].first { $0?.isEmpty == false }??.first ?? n
            let available = max(0, next - previous - 1)
            let word = words[j]
            let closest = word.allowed.min { a, b in
                let da = abs(a - available), db = abs(b - available)
                if da != db { return da < db }
                if (a == word.syllables) != (b == word.syllables) { return a == word.syllables }
                return a < b
            } ?? word.syllables
            let count = assigned[j]?.count
            return NucleusWordAssignment(
                available: available, dictionaryCount: word.syllables, short: assigned[j] == nil,
                confidence: max(0, confidence.splitExact - confidence.splitPerMismatch * Double(abs(available - closest))),
                allowed: word.allowed == [word.syllables] ? nil : word.allowed,
                assignedCount: count.flatMap { $0 == word.syllables ? nil : $0 })
        }
    }
}

/// The assignment's cost: short words first, then ms, then words off their context count. Costs within a
/// microsecond tie.
private struct Cost: Comparable {
    var short: Int
    var ms: Double
    var alternate: Int
    static let tolerance = 1e-6

    static func < (a: Cost, b: Cost) -> Bool {
        if a.short != b.short { return a.short < b.short }
        if abs(a.ms - b.ms) > tolerance { return a.ms < b.ms }
        return a.alternate < b.alternate
    }
    static func == (a: Cost, b: Cost) -> Bool {
        a.short == b.short && abs(a.ms - b.ms) <= tolerance && a.alternate == b.alternate
    }
    static func + (a: Cost, b: Cost) -> Cost {
        Cost(short: a.short + b.short, ms: a.ms + b.ms, alternate: a.alternate + b.alternate)
    }
}

// MARK: - Assignment stability (spec 26 §3)

public enum NucleusAssignmentStability {
    /// The words (indices into `words`) whose verdict differs between the DP's assignment and an alternative one.
    ///
    /// A word is edge-exposed when a nucleus peak (assigned or not) lies within `nucleus.ambiguityEdgeMs` of either of
    /// its edges. For each such peak, the alternative moves it across that edge: from the word to its neighbour, from
    /// the neighbour (or from no word) to the word, or, when the receiver can't take it under N_w (count, order or
    /// reach), out of its owner (skipped). A word whose remaining count leaves N_w is nucleus-short in the
    /// alternative. Every word the move touches is re-verdicted with `verdict` (given its index, its nuclei or nil when
    /// short, and its assignment under that alternative); a word whose verdict differs is ambiguous. Words with no
    /// peak near an edge are never ambiguous.
    public static func ambiguousWords<Verdict: Equatable>(
        peaks: [Double], words: [NucleusAssigner.Word], result: NucleusAssigner.Result, thresholds: Thresholds,
        verdict: (_ word: Int, _ nuclei: [Int]?, _ assignment: NucleusWordAssignment) -> Verdict
    ) -> Set<Int> {
        let edge = thresholds.nucleus.ambiguityEdgeMs / 1000 + 1e-9
        let padding = thresholds.alignment.asrPaddingMs
        let base = result.nuclei
        var owner: [Int: Int] = [:]
        for (j, list) in base.enumerated() { for i in list ?? [] { owner[i] = j } }
        var baseVerdicts: [Int: Verdict] = [:]
        func baseVerdict(_ j: Int) -> Verdict {
            if let v = baseVerdicts[j] { return v }
            let v = verdict(j, base[j], result.words[j])
            baseVerdicts[j] = v
            return v
        }

        /// Whether word `j` can take nucleus `i` on top of `list` (nil: short, no nuclei): in reach, count in N_w,
        /// and no other word's nucleus between them (monotonic).
        func canTake(_ j: Int, _ i: Int, _ assigned: [[Int]?]) -> [Int]? {
            let list = assigned[j] ?? []
            guard words[j].outsideMs(peaks[i]) <= padding + 1e-6, words[j].allowed.contains(list.count + 1)
            else { return nil }
            let merged = (list + [i]).sorted()
            let low = merged.first!, high = merged.last!
            for (k, other) in assigned.enumerated() where k != j {
                if (other ?? []).contains(where: { $0 > low && $0 < high }) { return nil }
            }
            return merged
        }
        func removing(_ i: Int, from j: Int, _ assigned: inout [[Int]?]) {
            let rest = (assigned[j] ?? []).filter { $0 != i }
            assigned[j] = words[j].allowed.contains(rest.count) ? rest : nil
        }

        var ambiguous = Set<Int>()
        for j in words.indices {
            for i in peaks.indices {
                let nearStart = abs(peaks[i] - words[j].start) <= edge
                let nearEnd = abs(peaks[i] - words[j].end) <= edge
                guard nearStart || nearEnd else { continue }
                var neighbours: [Int] = []
                if nearStart && j > 0 { neighbours.append(j - 1) }
                if nearEnd && j + 1 < words.count { neighbours.append(j + 1) }
                if neighbours.isEmpty { neighbours = [-1] }
                for neighbour in neighbours {
                    var alternative = base
                    var touched: Set<Int> = [j]
                    if neighbour >= 0 { touched.insert(neighbour) }
                    let from = owner[i]
                    if from == j {
                        removing(i, from: j, &alternative)
                        if neighbour >= 0, let taken = canTake(neighbour, i, alternative) { alternative[neighbour] = taken }
                    } else if let from, from == neighbour {
                        removing(i, from: from, &alternative)
                        if let taken = canTake(j, i, alternative) { alternative[j] = taken }
                    } else if from == nil {
                        guard let taken = canTake(j, i, alternative) else { continue }
                        alternative[j] = taken
                    } else {
                        continue
                    }
                    if let from { touched.insert(from) }
                    let altResults = NucleusAssigner.results(
                        alternative, words: words, nucleusCount: peaks.count, thresholds: thresholds)
                    for k in touched where verdict(k, alternative[k], altResults[k]) != baseVerdict(k) {
                        ambiguous.insert(k)
                    }
                }
            }
        }
        return ambiguous
    }
}

// MARK: - Measurement (§3)

extension NucleusMeasurement {
    /// The features of the syllable whose nucleus is `nuclei[index]`.
    static func measure(_ index: Int, of nuclei: [Nucleus], take: TakeSignal, pitch: PitchTrack,
                        thresholds: Thresholds) -> NucleusMeasurement {
        let nucleus = nuclei[index]
        let reach = thresholds.nucleus.windowMs / 1000
        let window = SyllableSegmenter.range(
            max(nucleus.peakTime - reach, nucleus.region.start), min(nucleus.peakTime + reach, nucleus.region.end))
        return NucleusMeasurement(
            nucleusIndex: index, peakTime: nucleus.peakTime, region: nucleus.region, duration: nucleus.region.duration,
            energyDBFS: max(take.rmsDBFS(in: window), thresholds.prominence.energyMinimumDBFS),
            peakSemitones: pitch.peakSemitones(
                in: nucleus.region, minVoicedFrames: Int(thresholds.prominence.pitchMinVoicedFrames)))
    }
}
