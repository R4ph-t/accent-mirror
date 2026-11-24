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
    /// s_w: `splitExact` − `splitPerMismatch` · |P − N_w|, floored at 0 (spec 07's rule, unchanged).
    public let confidence: Double

    public init(available: Int, dictionaryCount: Int, short: Bool, confidence: Double) {
        self.available = available
        self.dictionaryCount = dictionaryCount
        self.short = short
        self.confidence = confidence
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
    func detect(envelope: [Double], voiced: [Bool]) -> [Nucleus] {
        let settings = thresholds.nucleus
        let count = envelope.count
        guard count >= 3 else { return [] }
        func isVoiced(_ frame: Int) -> Bool { frame < voiced.count && voiced[frame] }

        // Candidates: voiced local maxima at or above the level floor.
        var peaks = (1..<(count - 1)).filter { frame in
            envelope[frame] >= envelope[frame - 1] && envelope[frame] > envelope[frame + 1] && isVoiced(frame)
                && envelope[frame] >= settings.minPeakDBFS
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
            var runStart = peak, runEnd = peak
            while runStart > 0 && isVoiced(runStart - 1) { runStart -= 1 }
            while runEnd + 1 < count && isVoiced(runEnd + 1) { runEnd += 1 }
            // The region: voiced, within `regionDropDB` of the peak, never reaching a valley to a neighbour.
            let floor = envelope[peak] - settings.regionDropDB
            var first = peak, last = peak
            while first - 1 > leftValley && isVoiced(first - 1) && envelope[first - 1] >= floor { first -= 1 }
            while last + 1 < rightValley && isVoiced(last + 1) && envelope[last + 1] >= floor { last += 1 }
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
    static func voicedCells(_ pitch: PitchTrack, count: Int) -> [Bool] {
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
        /// N_w, the dictionary syllable count.
        public let syllables: Int

        public init(start: Double, end: Double, syllables: Int) {
            self.start = start
            self.end = end
            self.syllables = syllables
        }
    }

    public struct Result: Sendable, Hashable {
        /// Per word, the indices of its N_w nuclei in order, or nil when nucleus-short.
        public let nuclei: [[Int]?]
        /// Per word, its assignment (P, short, s_w).
        public let words: [NucleusWordAssignment]
    }

    /// The monotonic assignment: each word gets exactly N_w consecutive nuclei or is marked short. Cost of a nucleus in
    /// a word: how far (ms) its peak lies outside the word's unpadded span; a nucleus further than
    /// `alignment.asrPaddingMs` outside can't be assigned to that word. Skipping a nucleus costs `nucleus.skipCostMs`.
    /// The program minimises the number of short words first, then the cost; ties go to the earlier word.
    public static func assign(_ nuclei: [Double], to words: [Word], thresholds: Thresholds = .current) -> Result {
        let n = nuclei.count, m = words.count
        let skip = thresholds.nucleus.skipCostMs
        let padding = thresholds.alignment.asrPaddingMs

        /// The cost of word j taking nuclei i..<i+N_j; nil when one is out of reach or there are too few.
        func take(_ i: Int, _ j: Int) -> Cost? {
            let count = words[j].syllables
            guard count > 0, i + count <= n else { return nil }
            var total = 0.0
            for k in i..<(i + count) {
                let t = nuclei[k]
                let outside = max(0, words[j].start - t, t - words[j].end) * 1000
                guard outside <= padding + Cost.tolerance else { return nil }
                total += outside
            }
            return Cost(short: 0, ms: total)
        }

        // best[i][j]: least cost to finish from nucleus i, word j.
        var best = Array(repeating: Array(repeating: Cost(short: Int.max / 4, ms: 0), count: m + 1), count: n + 1)
        for i in stride(from: n, through: 0, by: -1) {
            for j in stride(from: m, through: 0, by: -1) {
                if i == n && j == m { best[i][j] = Cost(short: 0, ms: 0); continue }
                var options: [Cost] = []
                if j < m, let c = take(i, j) { options.append(c + best[i + words[j].syllables][j + 1]) }
                if i < n { options.append(Cost(short: 0, ms: skip) + best[i + 1][j]) }
                if j < m { options.append(Cost(short: 1, ms: 0) + best[i][j + 1]) }
                best[i][j] = options.min()!
            }
        }

        // Forward: at each state prefer giving the word its nuclei now, then skipping a nucleus, then short. Taking
        // now gives a contested nucleus to the earlier word.
        var assigned = [[Int]?](repeating: nil, count: m)
        var i = 0, j = 0
        while i < n || j < m {
            let target = best[i][j]
            if j < m, let c = take(i, j), c + best[i + words[j].syllables][j + 1] == target {
                assigned[j] = Array(i..<(i + words[j].syllables))
                i += words[j].syllables
                j += 1
            } else if i < n, Cost(short: 0, ms: skip) + best[i + 1][j] == target {
                i += 1
            } else {
                j += 1
            }
        }

        // P from the assignment (CTO markup 1): nuclei strictly between the neighbours' assigned nuclei.
        let confidence = thresholds.confidence
        let results = (0..<m).map { j -> NucleusWordAssignment in
            let previous = assigned[..<j].last { $0 != nil }??.last ?? -1
            let next = assigned[(j + 1)...].first { $0 != nil }??.first ?? n
            let available = max(0, next - previous - 1)
            let count = words[j].syllables
            return NucleusWordAssignment(
                available: available, dictionaryCount: count, short: assigned[j] == nil,
                confidence: max(0, confidence.splitExact - confidence.splitPerMismatch * Double(abs(available - count))))
        }
        return Result(nuclei: assigned, words: results)
    }
}

/// The assignment's cost: short words first, then ms. Costs within a microsecond tie.
private struct Cost: Comparable {
    var short: Int
    var ms: Double
    static let tolerance = 1e-6

    static func < (a: Cost, b: Cost) -> Bool { a.short != b.short ? a.short < b.short : a.ms < b.ms - tolerance }
    static func == (a: Cost, b: Cost) -> Bool { a.short == b.short && abs(a.ms - b.ms) <= tolerance }
    static func + (a: Cost, b: Cost) -> Cost { Cost(short: a.short + b.short, ms: a.ms + b.ms) }
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
