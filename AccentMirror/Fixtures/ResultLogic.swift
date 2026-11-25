import Foundation

// The v3/v3.1 result rules (spec 29), as pure functions of fixture values. UI-free on purpose: no SwiftUI, no AMCore,
// so the unhosted `AccentMirrorTests` compile this very file (through the `AccentMirrorTests/ResultLogic.swift`
// symlink) without launching the app. Nothing here reads a verdict: v1 shows, it never judges.

// MARK: - Dictionary stress (v3.1 V2)

enum StressMarks {
    /// The syllable that carries the Lime dot and the bold caps: the word's single context-resolved primary (spec 28
    /// `expectedStress`, from the starter override or the part-of-speech variant). Never the raw CMUdict primary: a
    /// word without `expectedStress` is ambiguous and gets neither.
    static func dottedSyllable(_ word: NativeWord) -> Int? {
        guard let stress = word.expectedStress, stress.count == word.syllables.count else { return nil }
        let primaries = stress.indices.filter { stress[$0] == .primary }
        return primaries.count == 1 ? primaries[0] : nil
    }

    /// OOV, or no single context pronunciation: no dot, no caps, and the "can be said more than one way" tooltip.
    static func isAmbiguous(_ word: NativeWord) -> Bool {
        guard let stress = word.expectedStress, stress.count == word.syllables.count else { return true }
        return stress.filter { $0 == .primary }.count > 1
    }
}

// MARK: - Card 1's quiet line (v3 §3.1)

/// At most one quiet line under the result row; the first that applies wins.
enum ResultQuietLine: Equatable, Sendable {
    /// v3.5 I4 tier B: a run of frames at −1 dBFS lasted 50 ms or more (the take is saved). First in the order.
    case clipped
    /// `comparableCoverage` is known and below `minimumCoverage`.
    case lowCoverage
    case roughTiming
    /// The heard words you added, in order.
    case insertions([String])

    static func first(clipped: Bool = false, comparableCoverage: Double?, minimumCoverage: Double,
                      timing: Analysis.Timing?, insertions: [String]) -> ResultQuietLine? {
        if clipped { return .clipped }
        if let coverage = comparableCoverage, coverage < minimumCoverage { return .lowCoverage }
        if timing == .rough { return .roughTiming }
        if !insertions.isEmpty { return .insertions(insertions) }
        return nil
    }

    /// The words a take adds to the phrase (`inserted` pairs), as heard.
    static func insertedWords(_ take: TakeFixture?) -> [String] {
        (take?.words ?? []).filter { $0.kind == .inserted }.compactMap(\.heard)
    }
}

// MARK: - Earlier takes (v3 §3.3)

struct EarlierTakeLine: Equatable, Sendable {
    var number: Int?
    /// `pitch.you` at this opacity, 1 pt.
    var opacity: Double
    var segments: [[PitchPoint]]

    static func == (a: Self, b: Self) -> Bool {
        a.number == b.number && a.opacity == b.opacity && a.segments.map { $0.map(\.t) } == b.segments.map { $0.map(\.t) }
    }
}

enum EarlierTakes {
    /// Newest strongest.
    static let opacities: [Double] = [0.30, 0.20, 0.12]

    /// Up to the 3 previous saved takes, newest first. Unalignable takes are never drawn, and a stretch under 3
    /// frames isn't either (as for your line).
    static func lines(_ takes: [TakeFixture], visible: Bool) -> [EarlierTakeLine] {
        guard visible else { return [] }
        let drawable = takes.filter { $0.alignment == .aligned && $0.hasAudio }.prefix(opacities.count)
        return zip(drawable, opacities).map { take, opacity in
            EarlierTakeLine(number: take.number, opacity: opacity,
                            segments: take.pitch.filter { $0.points.count >= 3 }.map(\.points))
        }
    }

    /// Hovering a take in the open take menu: that take is the only ghost, at the strongest opacity.
    static func preview(_ take: TakeFixture) -> [EarlierTakeLine] {
        lines([take], visible: true)
    }
}

/// View ▸ Show Earlier Takes (⇧⌘G): on by default, remembered in `UserDefaults`.
struct EarlierTakesPreference {
    static let key = "ShowEarlierTakes"
    var defaults: UserDefaults

    var isOn: Bool { defaults.object(forKey: Self.key) as? Bool ?? true }

    func set(_ on: Bool) { defaults.set(on, forKey: Self.key) }

    @discardableResult
    func toggle() -> Bool {
        let next = !isOn
        set(next)
        return next
    }
}

// MARK: - Playback (Play Model ⌘L, Play You ⇧⌘L, Play Both ⌥⌘L)

/// A playback clock in seconds. The app uses the system's uptime; fixtures and tests inject their own.
protocol PlaybackClock: AnyObject {
    var now: Double { get }
}

final class SystemPlaybackClock: PlaybackClock {
    var now: Double { ProcessInfo.processInfo.systemUptime }
}

/// A clock that only moves when told to: fixtures freeze Play Both with it, tests drive it.
final class FrozenPlaybackClock: PlaybackClock {
    var now: Double
    init(now: Double) { self.now = now }
}

/// What plays, in order. Play Both is the model's phrase, a 0.4 s pause, then your take.
struct PlaybackSchedule: Equatable, Sendable {
    enum Side: Equatable, Sendable { case model, you }

    enum Step: Equatable, Sendable {
        /// Plays `seconds` of a side, sweeping its own timeline from `from` to `to` (0…1; a word's slice when looping).
        case play(Side, seconds: Double, from: Double = 0, to: Double = 1)
        case pause(seconds: Double)

        var seconds: Double {
            switch self {
            case .play(_, let seconds, _, _), .pause(let seconds): seconds
            }
        }
    }

    enum Phase: Equatable, Sendable {
        /// The playhead is at `progress` (0…1) along that side's own timeline.
        case playing(Side, progress: Double)
        case pause
        case finished
    }

    static let pauseSeconds = 0.4

    var steps: [Step]
    /// A label click loops until Esc (v3 §3.5).
    var repeats = false

    static func model(_ seconds: Double) -> Self { Self(steps: [.play(.model, seconds: seconds)]) }
    static func you(_ seconds: Double) -> Self { Self(steps: [.play(.you, seconds: seconds)]) }
    static func both(model: Double, you: Double) -> Self {
        Self(steps: [.play(.model, seconds: model), .pause(seconds: pauseSeconds), .play(.you, seconds: you)])
    }

    /// Clicking a word's label: the model's slice, 0.4 s, your slice, over and over until Esc. A missing word (no
    /// slice of yours) loops the model's slice only.
    static func loop(model: (from: Double, to: Double, seconds: Double),
                     you: (from: Double, to: Double, seconds: Double)?) -> Self {
        var steps: [Step] = [.play(.model, seconds: model.seconds, from: model.from, to: model.to), .pause(seconds: pauseSeconds)]
        if let you { steps += [.play(.you, seconds: you.seconds, from: you.from, to: you.to), .pause(seconds: pauseSeconds)] }
        return Self(steps: steps, repeats: true)
    }

    /// The model's slice alone, repeating with no pause (v3.2 W1: a word loop with no take of yours).
    static func loopModel(_ model: (from: Double, to: Double, seconds: Double)) -> Self {
        Self(steps: [.play(.model, seconds: model.seconds, from: model.from, to: model.to)], repeats: true)
    }

    var totalSeconds: Double { steps.map(\.seconds).reduce(0, +) }

    /// After a full-window play, or a slice that ends at the last word (`to == 1`), play through the true end
    /// of the clip (`tailSeconds`) and hold the playhead at the end of the word. Word loops of earlier words are unchanged.
    func applyingTail(model: AudioClip?, you: AudioClip?) -> PlaybackSchedule {
        var out: [Step] = []
        for step in steps {
            out.append(step)
            guard case .play(let side, _, _, let to) = step, to == 1 else { continue }
            let tail = (side == .model ? model : you)?.tailSeconds ?? 0
            if tail > 0 { out.append(.play(side, seconds: tail, from: 1, to: 1)) }
        }
        return PlaybackSchedule(steps: out, repeats: repeats)
    }

    func phase(at elapsed: Double) -> Phase {
        guard elapsed >= 0 else { return steps.isEmpty ? .finished : phase(at: 0) }
        if repeats, totalSeconds > 0, elapsed >= totalSeconds {
            return phase(at: elapsed.truncatingRemainder(dividingBy: totalSeconds))
        }
        var start = 0.0
        for step in steps {
            let end = start + step.seconds
            if elapsed < end {
                switch step {
                case .play(let side, let seconds, let from, let to):
                    let fraction = seconds > 0 ? (elapsed - start) / seconds : 0
                    return .playing(side, progress: from + (to - from) * fraction)
                case .pause:
                    return .pause
                }
            }
            start = end
        }
        return .finished
    }
}

/// One run of a schedule on a clock. Esc (`stop`) ends it at once.
final class PlaybackRun {
    let schedule: PlaybackSchedule
    private let clock: any PlaybackClock
    private let startedAt: Double
    private var stoppedAt: Double?

    init(_ schedule: PlaybackSchedule, clock: any PlaybackClock) {
        self.schedule = schedule
        self.clock = clock
        startedAt = clock.now
    }

    var elapsed: Double { (stoppedAt ?? clock.now) - startedAt }

    var phase: PlaybackSchedule.Phase { stoppedAt == nil ? schedule.phase(at: elapsed) : .finished }

    var isFinished: Bool { phase == .finished }

    func stop() {
        if stoppedAt == nil { stoppedAt = clock.now }
    }
}

// MARK: - Timing connectors (v3 §3.2, v3.1 V2)

/// A 1 pt line from a native syllable to your matching one. No connector for a missing or an inserted word.
struct TimingConnector: Equatable, Sendable {
    /// The native syllable's centre on the native timeline (0…1).
    var native: Double
    /// Your syllable's centre on your timeline (0…1).
    var you: Double
    /// The native syllable carries the dot: the line starts 4 pt below it (label top + 23, not + 17).
    var fromDot: Bool
}

enum TimingConnectors {
    /// The native word each of the take's aligned pairs stands for (nil for an inserted word), in the same walk the
    /// connectors use.
    static func nativeWordIndices(phrase: PhraseFixture, take: TakeFixture) -> [Int?] {
        var nativeIndex = 0
        return take.words.map { pair in
            guard pair.kind != .inserted else { return nil }
            defer { nativeIndex += 1 }
            return phrase.words.indices.contains(nativeIndex) ? nativeIndex : nil
        }
    }

    /// Pairs the phrase's words with the take's aligned word pairs in order (spec 28's alignment), then syllables by
    /// index within each word. Missing words advance past their native word with no line; inserted words have no
    /// native word.
    static func connectors(phrase: PhraseFixture, take: TakeFixture) -> [TimingConnector] {
        var out: [TimingConnector] = []
        var nativeIndex = 0
        for pair in take.words {
            switch pair.kind {
            case .inserted:
                continue
            case .missing:
                nativeIndex += 1
            case .present, .substituted:
                guard phrase.words.indices.contains(nativeIndex) else { return out }
                let word = phrase.words[nativeIndex]
                let dot = StressMarks.dottedSyllable(word)
                for index in 0..<min(word.syllables.count, pair.syllables.count) {
                    let n = word.syllables[index], y = pair.syllables[index]
                    out.append(TimingConnector(native: (n.start + n.end) / 2, you: (y.start + y.end) / 2,
                                               fromDot: dot == index))
                }
                nativeIndex += 1
            }
        }
        return out
    }
}

// MARK: - Inspector THIS TAKE (v3 §4, v3.1 V4)

/// One row: the measure, your value and the native range, all plain. Nothing marks a value outside the range.
struct MeasureRow: Equatable, Sendable {
    var name: String
    var nameTooltip: String?
    var you: String
    /// The reason when your value is "—".
    var youTooltip: String?
    var native: String
    var nativeTooltip: String?
}

enum ThisTake {
    static let title = "THIS TAKE"
    static let headers = (measure: "MEASURE", you: "YOU", native: "NATIVE RANGE")
    static let rhythmTooltip = "How much syllable lengths change from one syllable to the next."
    static let missing = "\u{2014}"
    static let alignmentTitle = "ALIGNMENT"
    static let alignmentNote = "how closely your syllables lined up"

    static func alignment(_ timing: Analysis.Timing) -> String {
        switch timing {
        case .good: "Clear"
        case .rough: "Rough"
        }
    }

    static func rows(_ d: Describe) -> [MeasureRow] {
        [
            row("Length", d.you.lengthSeconds, d.native.lengthSeconds, digits: 1, unit: " s"),
            row("Syllables per s", d.you.syllablesPerSecond, d.native.syllablesPerSecond, digits: 1, unit: ""),
            row("Pitch range", d.you.pitchRangeSemitones, d.native.pitchRangeSemitones, digits: 0, unit: " st"),
            with(row("Rhythm (nPVI)", d.you.rhythmNPVI, d.native.rhythmNPVI, digits: 0, unit: "")) {
                $0.nameTooltip = rhythmTooltip
            },
            MeasureRow(
                name: "Ends", nameTooltip: nil,
                you: d.you.endingDirection.map(direction) ?? missing,
                youTooltip: d.you.endingDirection == nil ? reason(.tooFewFinalFrames) : nil,
                native: endings(d.native.endingDirections), nativeTooltip: nil
            ),
        ]
    }

    /// "Native range is the spread across the 8 native voices for this phrase." Nil for a single native take, whose
    /// own values the column shows (spec gap: no copy for one voice).
    static func note(_ d: Describe) -> String? {
        d.native.voices > 1 ? "Native range is the spread across the \(d.native.voices) native voices for this phrase." : nil
    }

    static func reason(_ reason: Describe.MissingReason) -> String {
        switch reason {
        case .noVoicedFrames: "No pitch was found where this measure reads."
        case .tooFewSyllables: "This needs at least 3 syllables."
        case .tooFewFinalFrames: "Too little pitch at the end of the take to read its direction."
        case .noWords: "None of the phrase\u{2019}s words were heard."
        }
    }

    static func direction(_ direction: Describe.Direction) -> String {
        switch direction {
        case .rise: "rising"
        case .fall: "falling"
        case .level: "level"
        }
    }

    /// "5 falling, 3 rising": most first; one voice reads as its own direction.
    static func endings(_ counts: [String: Int]) -> String {
        let known = counts.compactMap { key, count in Describe.Direction(rawValue: key).map { ($0, count) } }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : order($0.0) < order($1.0) }
        guard !known.isEmpty else { return missing }
        if known.count == 1, known[0].1 == 1 { return direction(known[0].0) }
        return known.map { "\($0.1) \(direction($0.0))" }.joined(separator: ", ")
    }

    private static func order(_ d: Describe.Direction) -> Int { Describe.Direction.allCases.firstIndex(of: d) ?? 0 }

    private static func row(_ name: String, _ you: Describe.Value, _ native: Describe.Range, digits: Int, unit: String)
        -> MeasureRow {
        MeasureRow(
            name: name, nameTooltip: nil,
            you: you.value.map { number($0, digits) + unit } ?? missing,
            youTooltip: you.value == nil ? reason(you.reason ?? .noVoicedFrames) : nil,
            native: range(native, digits: digits, unit: unit),
            nativeTooltip: native.min == nil ? reason(.noVoicedFrames) : nil
        )
    }

    static func range(_ r: Describe.Range, digits: Int, unit: String) -> String {
        guard let low = r.min, let high = r.max else { return missing }
        let a = number(low, digits), b = number(high, digits)
        return (a == b ? a : "\(a)\u{2013}\(b)") + unit
    }

    static func number(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    private static func with(_ row: MeasureRow, _ change: (inout MeasureRow) -> Void) -> MeasureRow {
        var copy = row
        change(&copy)
        return copy
    }
}
