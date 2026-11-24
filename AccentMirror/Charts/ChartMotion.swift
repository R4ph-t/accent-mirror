import Foundation

// Spec 20: the strip and pitch cards' motion, as pure functions of the inputs and a clock time. UI-free on purpose (no
// SwiftUI, no AMCore): fixtures freeze the clock, so screenshots and tests see exactly one frame.

// MARK: - Eases

enum ChartMotion {
    /// Hover and loop boxes fade in (Addendum r6 E3).
    static let highlightFade = 0.120
    /// View ▸ Show Earlier Takes (⇧⌘G) fades the ghosts out or in (v3 §3.3).
    static let earlierTakesToggle = 0.120
    /// A newly saved take fades in as the oldest ghost drops out.
    static let earlierTakeSaved = 0.150
    /// The band, your line, the strip and the connectors re-time onto a new voice in one ease (§13 item 9).
    static let voiceSwitch = 0.150

    /// Ease in and out (smoothstep): 0 at the start, ½ halfway, 1 at the end, flat at both ends.
    static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

/// One timed change on the chart clock.
struct ChartTransition: Equatable, Sendable {
    var start: Double
    var duration: Double

    /// Eased progress, 0…1. With Reduce Motion the change is already done.
    func progress(at now: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, duration > 0 else { return 1 }
        return ChartMotion.ease((now - start) / duration)
    }

    func isRunning(at now: Double) -> Bool { now < start + duration }
}

func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }

// MARK: - Pitch axis (§9, §13 item 7)

enum PitchAxis {
    static let step = 6.0
    static let maximum = 24.0

    /// The largest distance from your median the data reaches, band edges included.
    static func needed(_ pitch: PitchPresentation) -> Double {
        let band = pitch.band.flatMap(\.points).map { abs($0.st) + $0.half }
        let you = pitch.you.flatMap(\.points).map { abs($0.st) }
        let earlier = pitch.earlier.flatMap { $0.segments.flatMap { $0 } }.map { abs($0.st) }
        return (band + you + earlier).max() ?? 0
    }

    /// The half-range in 6 st steps up to ±24, never below `floor`: the axis grows and never shrinks within a phrase.
    static func range(needed: Double, floor: Double) -> Double {
        let stepped = min(maximum, max(step, (needed / step).rounded(.up) * step))
        return min(maximum, max(floor, stepped))
    }
}

// MARK: - Earlier takes (v3 §3.3)

enum GhostBlend {
    /// Cross-fades the drawn ghosts from `from` to `to`: a take in both moves to its new opacity, a new one fades in
    /// and one that left fades out. Takes are matched by number. Newest first; takes on their way out go last, so
    /// they are drawn underneath.
    static func blend(from: [EarlierTakeLine], to: [EarlierTakeLine], progress p: Double) -> [EarlierTakeLine] {
        func key(_ line: EarlierTakeLine, _ index: Int) -> String { line.number.map(String.init) ?? "unsaved-\(index)" }
        let before = Dictionary(from.enumerated().map { (key($1, $0), $1) }, uniquingKeysWith: { a, _ in a })
        let afterKeys = Set(to.enumerated().map { key($1, $0) })
        var out: [EarlierTakeLine] = to.enumerated().map { index, line in
            var drawn = line
            drawn.opacity = lerp(before[key(line, index)]?.opacity ?? 0, line.opacity, p)
            return drawn
        }
        for (index, line) in from.enumerated() where !afterKeys.contains(key(line, index)) {
            var drawn = line
            drawn.opacity = lerp(line.opacity, 0, p)
            out.append(drawn)
        }
        return out.filter { $0.opacity > 0.0001 }
    }
}

// MARK: - Live recording strip (§7, A3, r6 E9)

/// The envelope stream spec 14 publishes while recording: one RMS value (0…1) per 10 ms.
struct RecordingEnvelope: Equatable, Sendable {
    static let hop = 0.01
    var rms: [Double]

    var elapsed: Double { Double(rms.count) * Self.hop }

    /// A deterministic stand-in for fixtures: your take's syllables, said over and over every `takeSeconds`, with a
    /// little texture, for `elapsed` seconds.
    static func synthetic(syllables: [StripCluster], takeSeconds: Double, elapsed: Double) -> RecordingEnvelope {
        let count = max(0, Int((elapsed / hop).rounded()))
        let rms = (0..<count).map { index -> Double in
            let t = Double(index) * hop
            let u = t.truncatingRemainder(dividingBy: max(takeSeconds, hop)) / max(takeSeconds, hop)
            guard let syllable = syllables.first(where: { $0.start <= u && u < $0.end }) else {
                return 0.02 + 0.02 * barJitterValue(7, index)
            }
            let local = (u - syllable.start) / max(syllable.end - syllable.start, 0.0001)
            let shape = pow(sin(Double.pi * local), 0.8)
            return syllable.prominence * shape * (0.6 + 0.4 * barJitterValue(syllable.seed, index))
        }
        return RecordingEnvelope(rms: rms)
    }
}

/// The live row's time scale (E9): x = elapsed ÷ the model's duration × plot width. A take longer than the model
/// compresses the whole row to fit, so the playhead stays at the right edge.
enum RecordingScale {
    /// Seconds of audio the plot width stands for.
    static func span(elapsed: Double, modelSeconds: Double) -> Double { max(modelSeconds, elapsed, RecordingEnvelope.hop) }

    /// The playhead, 0…1 across the plot.
    static func playhead(elapsed: Double, modelSeconds: Double) -> Double {
        min(1, elapsed / span(elapsed: elapsed, modelSeconds: modelSeconds))
    }
}

/// Pre-binned bar geometry for the live row: 1.5 pt bars on a 3 pt pitch, each bin the loudest 10 ms frame in it.
/// While the take is shorter than the model the bin width is fixed, so each frame only folds in the new samples.
/// Once the take runs past the model the bins widen with it and are rebuilt.
struct EnvelopeBins: Equatable, Sendable {
    static let pitch = 3.0
    static let barWidth = 1.5

    private(set) var secondsPerBin: Double = 0
    /// Bin heights, 0…1.
    private(set) var heights: [Double] = []
    /// Samples folded in so far.
    private(set) var consumed = 0
    /// How many times the bins were rebuilt from scratch (tests).
    private(set) var rebuilds = 0

    mutating func update(_ envelope: RecordingEnvelope, plotWidth: Double, modelSeconds: Double) {
        guard plotWidth > 0 else { return }
        let span = RecordingScale.span(elapsed: envelope.elapsed, modelSeconds: modelSeconds)
        let perBin = span * Self.pitch / plotWidth
        if perBin != secondsPerBin || envelope.rms.count < consumed {
            secondsPerBin = perBin
            heights = []
            consumed = 0
            rebuilds += 1
        }
        guard envelope.rms.count > consumed else { return }
        for index in consumed..<envelope.rms.count {
            let bin = Int((Double(index) * RecordingEnvelope.hop + 1e-9) / secondsPerBin)
            while heights.count <= bin { heights.append(0) }
            heights[bin] = max(heights[bin], min(1, max(0, envelope.rms[index])))
        }
        consumed = envelope.rms.count
    }

    static func binned(_ envelope: RecordingEnvelope, plotWidth: Double, modelSeconds: Double) -> EnvelopeBins {
        var bins = EnvelopeBins()
        bins.update(envelope, plotWidth: plotWidth, modelSeconds: modelSeconds)
        return bins
    }
}

/// The texture jitter, 0…1, deterministic (shared with the strip's bars).
func barJitterValue(_ seed: Int, _ index: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: seed &* 73_856_093 ^ index &* 19_349_663) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x % 10_000) / 10_000
}

// MARK: - Playhead (§9, v1 §5.3)

/// Your time and model time, both as fractions of their own timelines. Spec 09's `TimeWarp` behind it
/// (`WarpTimeMap`): nil inside a gap, a missing or an inserted word, and past the end clamp.
protocol ChartTimeMap: Sendable {
    func toModel(_ you: Double) -> Double?
    func toYou(_ model: Double) -> Double?
    /// The model time where the last mapped stretch before your time `you` ends: where the pitch playhead holds
    /// across a youOnly stretch.
    func gapEdge(beforeYou you: Double) -> Double?
}

/// What is playing, and where, on its own timeline (0…1). Spec 21 feeds it from the player.
struct PlaybackPosition: Equatable, Sendable {
    var side: PlaybackSchedule.Side
    var position: Double
}

/// Where the 1 pt playhead is drawn: on each strip row's own timeline and on the pitch plot's model timeline. Nil:
/// no playhead there.
struct PlayheadPlacement: Equatable, Sendable {
    var native: Double?
    var you: Double?
    var pitch: Double?

    static func place(_ playback: PlaybackPosition, map: (any ChartTimeMap)?) -> PlayheadPlacement {
        switch playback.side {
        case .model:
            return PlayheadPlacement(native: playback.position, you: map?.toYou(playback.position), pitch: playback.position)
        case .you:
            let model = map?.toModel(playback.position)
            // Across a youOnly stretch the pitch playhead holds at the gap edge; the native row shows none.
            return PlayheadPlacement(native: model, you: playback.position,
                                     pitch: model ?? map?.gapEdge(beforeYou: playback.position))
        }
    }
}

// MARK: - Syllable being played (r6 E4)

/// A native syllable and your matching one, as indices into the strip's two cluster lists.
struct SyllablePair: Equatable, Sendable {
    var native: Int
    var you: Int
}

enum PlayingSyllable {
    /// The syllable under the playhead on the row that plays, and its partner on the other row. Between syllables:
    /// none (the outline jumps, it never slides).
    static func outline(_ playback: PlaybackPosition, native: [StripCluster], you: [StripCluster],
                        pairs: [SyllablePair]) -> (native: Int?, you: Int?) {
        func index(in clusters: [StripCluster]) -> Int? {
            clusters.firstIndex { $0.start <= playback.position && playback.position <= $0.end }
        }
        switch playback.side {
        case .model:
            guard let n = index(in: native) else { return (nil, nil) }
            return (n, pairs.first { $0.native == n }?.you)
        case .you:
            guard let y = index(in: you) else { return (nil, nil) }
            return (pairs.first { $0.you == y }?.native, y)
        }
    }
}

// MARK: - Voice switch (§13 item 9)

enum VoiceBlend {
    /// The strip at `p` of the way from the old voice to the new: native syllables and connectors re-time; your row
    /// stays on your own timeline.
    static func strip(_ a: StripPresentation, _ b: StripPresentation, _ p: Double) -> StripPresentation {
        guard p < 1 else { return b }
        var out = b
        if a.native.count == b.native.count {
            out.native = zip(a.native, b.native).map { cluster($0, $1, p) }
        } else if p < 0.5 {
            out.native = a.native
        }
        if a.connectors.count == b.connectors.count {
            out.connectors = zip(a.connectors, b.connectors).map { x, y in
                TimingConnector(native: lerp(x.native, y.native, p), you: lerp(x.you, y.you, p), fromDot: y.fromDot)
            }
        } else if p < 0.5 {
            out.connectors = a.connectors
        }
        return out
    }

    /// The pitch card at `p`: the band, your line, the word labels and the texture re-time; the axis is the larger
    /// of the two. The band is never blanked.
    static func pitch(_ a: PitchPresentation, _ b: PitchPresentation, _ p: Double) -> PitchPresentation {
        guard p < 1 else { return b }
        var out = b
        out.rangeSemitones = max(a.rangeSemitones, b.rangeSemitones)
        out.band = band(a.band, b.band, p)
        out.you = line(a.you, b.you, p)
        if a.words.count == b.words.count {
            out.words = zip(a.words, b.words).map { x, y in
                (text: y.text, start: lerp(x.start, y.start, p), end: lerp(x.end, y.end, p), isTarget: y.isTarget)
            }
        }
        if a.texture.count == b.texture.count {
            out.texture = zip(a.texture, b.texture).map { cluster($0, $1, p) }
        }
        return out
    }

    private static func cluster(_ a: StripCluster, _ b: StripCluster, _ p: Double) -> StripCluster {
        var c = b
        c.start = lerp(a.start, b.start, p)
        c.end = lerp(a.end, b.end, p)
        c.prominence = lerp(a.prominence, b.prominence, p)
        return c
    }

    /// Point by point when both voices break the band the same way; resampled when the point counts differ; the old
    /// band until halfway, then the new, when the breaks differ.
    private static func band(_ a: [BandSegment], _ b: [BandSegment], _ p: Double) -> [BandSegment] {
        guard a.count == b.count else { return p < 0.5 ? a : b }
        return zip(a, b).map { x, y in
            let n = max(x.points.count, y.points.count)
            let xs = x.points.count == n ? x.points : resample(x.points, n)
            let ys = y.points.count == n ? y.points : resample(y.points, n)
            return BandSegment(points: zip(xs, ys).map { u, v in
                BandPoint(t: lerp(u.t, v.t, p), st: lerp(u.st, v.st, p), half: lerp(u.half, v.half, p))
            })
        }
    }

    private static func line(_ a: [PitchSegment], _ b: [PitchSegment], _ p: Double) -> [PitchSegment] {
        guard a.count == b.count, zip(a, b).allSatisfy({ $0.points.count == $1.points.count }) else { return p < 0.5 ? a : b }
        return zip(a, b).map { x, y in
            PitchSegment(points: zip(x.points, y.points).map { u, v in
                PitchPoint(t: lerp(u.t, v.t, p), st: lerp(u.st, v.st, p), voiced: v.voiced)
            })
        }
    }

    private static func resample(_ points: [BandPoint], _ count: Int) -> [BandPoint] {
        guard points.count > 1, count > 1 else { return Array(repeating: points.first ?? BandPoint(t: 0, st: 0, half: 0), count: count) }
        return (0..<count).map { i in
            let position = Double(i) / Double(count - 1) * Double(points.count - 1)
            let lower = Int(position), upper = min(lower + 1, points.count - 1)
            let f = position - Double(lower)
            let a = points[lower], b = points[upper]
            return BandPoint(t: lerp(a.t, b.t, f), st: lerp(a.st, b.st, f), half: lerp(a.half, b.half, f))
        }
    }
}
