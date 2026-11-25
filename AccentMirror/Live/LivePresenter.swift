import AMCore
import AMLibrary
import AMPipeline
import Foundation

// Spec 21: the one place AMCore names meet the UI's names (spec 01's "UI fixture drift" table). It turns the live
// pipeline's values into the fixture-shaped view state specs 19, 20 and 29 already draw, so `ShellPresenter` and the
// views stay as they are. UI-free on purpose (no SwiftUI): the unhosted `AccentMirrorTests` compile this file.
//
// Drift handled here, in one place:
// - `AnalysisOutcome.takeProblem(TakeProblem)` (one problem) → the fixture's `takeProblems: [..]` (first only).
// - `Stage` → the copy's four stage names (`OperationalError.Stage`).
// - `OperationalError.audioUnreadable` (no source) → `source: "take"` (only a take is read in v1).
// - `PersistenceStatus` with payloads → the fixture's bare `saved / notSaved / saveFailed / savedPruneFailed`.
// - `TimingLevel.poor` (no fixture name) → `rough`: ALIGNMENT reads Clear or Rough only (v3.1).
// - `DescribedMeasures` → `Describe` (same fields; `endingDirections` keyed by the direction's name).
// - Times in seconds on each speaker's timeline → fractions (0…1) of that timeline (`SCHEMA.md`); the model's
//   timeline is `AnalysisResult.modelAxis`, yours runs from your first heard word to your last.
// The v2 rows of the table (diff kinds, measure states, stress-line outcomes, inconclusive causes) aren't shown in
// v1 (show-don't-judge), so nothing maps them.

/// What the live shell shows for the selected phrase, before it becomes a fixture-shaped state.
struct LiveScreen: Sendable {
    enum Phase: Sendable, Equatable {
        case empty
        case recording(elapsedSeconds: Int)
        case analysing
        case showingTake
    }

    enum Shown: Sendable {
        case nothing
        /// An analysed take: saved with `number`, or not (yet) saved.
        case result(AnalysisResult, number: Int?)
        /// A take problem; `hasAudio` when You can play the attempt (too quiet, clipped, too short, words).
        case takeProblem(AMCore.TakeProblem, hasAudio: Bool)
    }

    var phase: Phase = .empty
    var shown: Shown = .nothing
    var operationalError: AMCore.OperationalError?
    var persistence: AMCore.PersistenceStatus?
    /// Saved take numbers, newest first.
    var savedTakes: [Int] = []
    /// Earlier takes behind yours, newest first (`TakeStore.ghosts(before:)`).
    var ghosts: [GhostPitch] = []
    /// Seconds of each side's audio, for playback and the playhead.
    var modelSeconds: Double?
    var youSeconds: Double?
}

/// The selected phrase and voice, from spec 15's manifest.
struct LivePhrase: Sendable {
    var phrase: StarterManifest.Phrase
    var packTitle: String
    var voice: RecordingID

    var recording: StarterManifest.Recording? { phrase.recording(voice) ?? phrase.recordings.first }
}

enum LivePresenter {
    /// The live state's fixture name: never a committed fixture's, so Samples ▸ shows no checkmark.
    static let fixtureName = ""

    // MARK: Library (spec 15)

    /// The sidebar's manifest: the starter packs in order, a pack with no phrases is "coming soon". No MY PHRASES
    /// while clip import hasn't shipped (E6): it would be empty.
    static func manifest(_ starter: StarterManifest) -> LibraryManifest {
        LibraryManifest(packs: starter.packs.map { pack in
            LibraryManifest.Pack(id: pack.id, title: pack.title, phrases: pack.phrases.compactMap { id in
                guard let phrase = starter.phrase(id) else { return nil }
                let words = phrase.text.split(separator: " ").map(String.init)
                let named = phrase.targets.compactMap { words.indices.contains($0) ? words[$0] : nil }
                return LibraryManifest.Phrase(id: id.rawValue, text: phrase.text, targets: named.isEmpty ? nil : named)
            })
        })
    }

    /// First run (v1 §4.2): the first phrase of the Stress Shifts pack, else the first phrase listed.
    static func firstPhrase(_ starter: StarterManifest) -> PhraseID? {
        let stress = starter.packs.first { $0.title.lowercased() == "stress shifts" || $0.id == "stress-shifts" }
        return stress?.phrases.first ?? starter.packs.lazy.flatMap(\.phrases).first ?? starter.phrases.first?.id
    }

    /// The pack a phrase is listed in.
    static func packTitle(_ starter: StarterManifest, phrase: PhraseID) -> String {
        starter.packs.first { $0.phrases.contains(phrase) }?.title ?? ""
    }

    // MARK: Voices (r6 E7)

    /// "Southern England (English)" for the pop-up row.
    static func voiceRow(_ recording: StarterManifest.Recording) -> String {
        "\(recording.region) (\(recording.accent))"
    }

    /// "p225 · F", right-aligned in the row (the F/M tag is Designer's call).
    static func voiceTag(_ recording: StarterManifest.Recording) -> String {
        let gender = recording.gender.prefix(1).uppercased()
        return gender.isEmpty ? recording.speaker : "\(recording.speaker) \u{00B7} \(gender)"
    }

    /// The pop-up's closed state: "Southern England · p225".
    static func voiceTitle(_ recording: StarterManifest.Recording) -> String {
        "\(recording.region) \u{00B7} \(recording.speaker)"
    }

    /// "Stress Shifts · Native speaker from Southern England, VCTK".
    static func subtitle(_ live: LivePhrase) -> String {
        guard let recording = live.recording else { return live.packTitle }
        let corpus = recording.corpus.uppercased().hasPrefix("VCTK") ? "VCTK" : recording.corpus
        return "\(live.packTitle) \u{00B7} Native speaker from \(recording.region), \(corpus)"
    }

    /// The inspector's attribution: speaker ID, corpus and licence.
    static func attribution(_ recording: StarterManifest.Recording) -> String {
        "\(recording.speaker), \(recording.corpus), \(recording.licence)"
    }

    // MARK: Drift (spec 01)

    static func takeProblem(_ problem: AMCore.TakeProblem) -> TakeProblem {
        switch problem {
        case .noMicrophone: .noMicrophone
        case .micDenied: .micDenied
        case .noSpeech: .noSpeech
        case .tooShort: .tooShort
        case .tooQuiet: .tooQuiet
        case .clipped: .clipped
        case .wordsDontMatch: .wordsDontMatch
        }
    }

    static func stage(_ stage: Stage) -> OperationalError.Stage {
        switch stage {
        case .decodeAudio, .recogniseWords, .alignWords: .findingWords
        case .trackPitch, .detectVoicing: .measuringPitch
        case .segmentSyllables, .measureStress: .measuringStress
        case .mapTime, .compare: .comparing
        }
    }

    static func operationalError(_ error: AMCore.OperationalError) -> OperationalError {
        switch error {
        case .modelUnavailable: OperationalError(kind: .modelUnavailable)
        case .inferenceFailed(let stage): OperationalError(kind: .inferenceFailed, stage: self.stage(stage))
        case .referenceCacheCorrupt: OperationalError(kind: .referenceCacheCorrupt)
        case .audioUnreadable: OperationalError(kind: .audioUnreadable, source: "take")
        }
    }

    /// `pending` shows nothing yet (the take reads as saved once it is).
    static func persistence(_ status: AMCore.PersistenceStatus) -> PersistenceStatus? {
        switch status {
        case .pending: nil
        case .saved: .saved
        case .notSaved: .notSaved
        case .saveFailed: .saveFailed
        case .savedPruneFailed: .savedPruneFailed
        }
    }

    static func timing(_ level: TimingLevel) -> Analysis.Timing {
        level == .good ? .good : .rough
    }

    static func describe(_ measures: DescribedMeasures) -> Describe {
        func value(_ v: DescribedValue) -> Describe.Value {
            switch v {
            case .value(let x): Describe.Value(value: x, reason: nil)
            case .missing(let reason): Describe.Value(value: nil, reason: Describe.MissingReason(rawValue: reason.rawValue))
            }
        }
        func range(_ r: DescribedRange) -> Describe.Range { Describe.Range(min: r.min, max: r.max, count: r.count) }
        let you = measures.you, native = measures.native
        return Describe(
            you: Describe.Speaker(
                lengthSeconds: value(you.lengthSeconds), syllablesPerSecond: value(you.syllablesPerSecond),
                pitchRangeSemitones: value(you.pitchRangeSemitones), rhythmNPVI: value(you.rhythmNPVI),
                endingDirection: you.endingDirection.flatMap { Describe.Direction(rawValue: $0.rawValue) }),
            native: Describe.Native(
                voices: native.voices, lengthSeconds: range(native.lengthSeconds),
                syllablesPerSecond: range(native.syllablesPerSecond),
                pitchRangeSemitones: range(native.pitchRangeSemitones), rhythmNPVI: range(native.rhythmNPVI),
                endingDirections: Dictionary(uniqueKeysWithValues: native.endingDirections.map { ($0.key.rawValue, $0.value) })))
    }

    // MARK: Timelines

    /// A time on a timeline as a fraction (0…1).
    static func fraction(_ t: Double, start: Double, end: Double) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, (t - start) / (end - start)))
    }

    /// Your own timeline: your first heard word's start to your last's end.
    static func yourSpan(_ result: AnalysisResult) -> (start: Double, end: Double) {
        let ranges = result.you.words.map(\.range)
        guard let start = ranges.map(\.start).min(), let end = ranges.map(\.end).max(), end > start else {
            let all = result.you.syllables.map(\.range)
            return (all.map(\.start).min() ?? 0, max(all.map(\.end).max() ?? 1, (all.map(\.start).min() ?? 0) + 0.01))
        }
        return (start, end)
    }

    // MARK: The native side

    /// The phrase's native side for the result's voice: words and syllables on the model timeline, the band.
    static func phrase(_ live: LivePhrase, result: AnalysisResult?) -> PhraseFixture {
        guard let result else { return emptyPhrase(live) }
        let axis = result.modelAxis
        let words: [NativeWord] = result.model.words.map { word in
            NativeWord(
                text: word.text, stressCheck: nil, expectedStress: word.expectedStress?.map(syllableStress),
                start: fraction(word.range.start, start: axis.start, end: axis.end),
                end: fraction(word.range.end, start: axis.start, end: axis.end),
                syllables: word.syllables.compactMap { index in
                    guard result.model.syllables.indices.contains(index) else { return nil }
                    let s = result.model.syllables[index]
                    return Syllable(
                        text: s.text, start: fraction(s.range.start, start: axis.start, end: axis.end),
                        end: fraction(s.range.end, start: axis.start, end: axis.end), prominence: s.prominence)
                })
        }
        return PhraseFixture(
            id: live.phrase.id.rawValue, text: live.phrase.text, subtitle: subtitle(live),
            rangeSemitones: rangeSemitones(result.pitchAxis), words: words, band: band(result))
    }

    /// Before any take: the phrase's words spread evenly, no bars or band yet (nothing has been analysed).
    static func emptyPhrase(_ live: LivePhrase) -> PhraseFixture {
        let texts = live.phrase.text.split(separator: " ").map(String.init)
        let step = 1 / Double(max(texts.count, 1))
        let words = texts.enumerated().map { index, text in
            NativeWord(text: text, stressCheck: nil, expectedStress: nil,
                       start: Double(index) * step, end: Double(index + 1) * step, syllables: [])
        }
        return PhraseFixture(id: live.phrase.id.rawValue, text: live.phrase.text, subtitle: subtitle(live),
                             rangeSemitones: 12, words: words, band: [])
    }

    static func syllableStress(_ stress: AMCore.SyllableStress) -> SyllableStress {
        switch stress {
        case .primary: .primary
        case .secondary: .secondary
        case .unstressed: .unstressed
        }
    }

    /// The chart's half-range: the larger side of `pitchAxis`.
    static func rangeSemitones(_ axis: ClosedRange<Double>) -> Double {
        max(abs(axis.lowerBound), abs(axis.upperBound), 6)
    }

    /// The native band on model time, one segment per stretch: a gap over 250 ms starts a new one.
    static func band(_ result: AnalysisResult) -> [BandSegment] {
        let axis = result.modelAxis
        var segments: [BandSegment] = []
        var current: [BandPoint] = []
        var last: Double?
        for point in result.nativeBand {
            if let last, point.time - last > 0.25, !current.isEmpty {
                segments.append(BandSegment(points: current))
                current = []
            }
            current.append(BandPoint(
                t: fraction(point.time, start: axis.start, end: axis.end), st: (point.lower + point.upper) / 2,
                half: max(0, (point.upper - point.lower) / 2)))
            last = point.time
        }
        if !current.isEmpty { segments.append(BandSegment(points: current)) }
        return segments
    }

    /// Pitch segments on model time (10 ms frames) as fractions of the model axis.
    static func pitch(_ segments: [AMCore.PitchSegment], axis: TimeRange, hop: Double = 0.01) -> [PitchSegment] {
        segments.map { segment in
            PitchSegment(points: segment.frames.enumerated().map { index, frame in
                PitchPoint(t: fraction(segment.start + Double(index) * hop, start: axis.start, end: axis.end),
                           st: frame.semitones, voiced: frame.voiced)
            })
        }.filter { !$0.points.isEmpty }
    }

    // MARK: Your side

    /// Your take as the strip and the pitch card draw it: aligned word pairs on your own timeline, your pitch on
    /// model time.
    static func take(_ result: AnalysisResult, number: Int?) -> TakeFixture {
        let span = yourSpan(result)
        var words: [AlignedWordPair] = []
        var yourWord = 0
        func yourIndex(for range: TimeRange) -> Int? {
            if let exact = result.you.words.firstIndex(where: { $0.range == range }) { return exact }
            return result.you.words.indices.contains(yourWord) ? yourWord : nil
        }
        func syllables(_ index: Int?) -> [Syllable] {
            guard let index else { return [] }
            return result.you.words[index].syllables.compactMap { s in
                guard result.you.syllables.indices.contains(s) else { return nil }
                let syllable = result.you.syllables[s]
                return Syllable(
                    text: syllable.text, start: fraction(syllable.range.start, start: span.start, end: span.end),
                    end: fraction(syllable.range.end, start: span.start, end: span.end), prominence: syllable.prominence)
            }
        }
        func expected(_ word: WordIndex) -> String? {
            result.model.words.indices.contains(word.rawValue) ? result.model.words[word.rawValue].text : nil
        }
        var lastEnd = 0.0
        var pendingMissing: [Int] = []
        for pair in result.alignment.pairs {
            switch pair {
            case .present(let phrase, let you):
                let index = yourIndex(for: you)
                words.append(AlignedWordPair(kind: .present, expected: expected(phrase), heard: nil, stressCheck: nil,
                                             syllables: syllables(index), slot: nil))
                yourWord = (index ?? yourWord) + 1
            case .substituted(let phrase, let heard, let you):
                let index = yourIndex(for: you)
                words.append(AlignedWordPair(kind: .substituted, expected: expected(phrase), heard: heard,
                                             stressCheck: nil, syllables: syllables(index), slot: nil))
                yourWord = (index ?? yourWord) + 1
            case .missing(let phrase):
                words.append(AlignedWordPair(kind: .missing, expected: expected(phrase), heard: nil, stressCheck: nil,
                                             syllables: [], slot: nil))
                pendingMissing.append(words.count - 1)
                continue
            case .inserted(let heard, let you, _):
                let index = yourIndex(for: you)
                words.append(AlignedWordPair(kind: .inserted, expected: nil, heard: heard, stressCheck: nil,
                                             syllables: syllables(index), slot: nil))
                yourWord = (index ?? yourWord) + 1
            }
            // A missing word's slot sits in the gap before the next heard word.
            let start = fraction(pair.yourRange?.start ?? 0, start: span.start, end: span.end)
            for missing in pendingMissing { words[missing].slot = (lastEnd + start) / 2 }
            pendingMissing = []
            lastEnd = fraction(pair.yourRange?.end ?? 0, start: span.start, end: span.end)
        }
        for missing in pendingMissing { words[missing].slot = min(1, lastEnd + 0.02) }
        return TakeFixture(
            id: result.takeID.rawValue, number: number, hasAudio: true, alignment: .aligned, level: .normal,
            words: words, pitch: pitch(result.youPitchOnModel, axis: result.modelAxis))
    }

    /// An earlier take, drawn as a ghost behind yours.
    static func ghost(_ ghost: GhostPitch, axis: TimeRange) -> TakeFixture {
        TakeFixture(id: ghost.take.id.rawValue, number: ghost.take.number, hasAudio: true, alignment: .aligned,
                    level: .normal, words: [], pitch: pitch(ghost.pitchOnModel, axis: axis))
    }

    /// The attempt behind a take problem: no analysis to draw, only that it was heard (or not).
    static func problemTake(hasAudio: Bool) -> TakeFixture {
        TakeFixture(id: "last-try", number: nil, hasAudio: hasAudio, alignment: .aligned, level: .nearSilent,
                    words: [], pitch: [])
    }

    // MARK: The state

    static func analysis(_ result: AnalysisResult) -> Analysis {
        Analysis(takeProblems: nil, verdict: Verdict(notScored: ()), timing: timing(result.timing),
                 comparableCoverage: result.comparableCoverage, describe: result.describe.map(describe))
    }

    /// The fixture-shaped state for `screen`, which `ShellModel.apply` draws exactly as it draws a committed fixture.
    static func loaded(_ live: LivePhrase, screen: LiveScreen, manifest: LibraryManifest) -> LoadedFixture {
        var result: AnalysisResult?
        var take: TakeFixture?
        var analysis: Analysis?
        switch screen.shown {
        case .nothing:
            break
        case .result(let analysed, let number):
            result = analysed
            take = Self.take(analysed, number: number)
            analysis = Self.analysis(analysed)
        case .takeProblem(let problem, let hasAudio):
            take = problemTake(hasAudio: hasAudio)
            analysis = Analysis(takeProblems: [takeProblem(problem)])
        }
        let phase: UIFixture.Phase
        var recording: UIFixture.Recording?
        switch screen.phase {
        case .empty: phase = take == nil ? .empty : .showingTake
        case .recording(let elapsed):
            phase = .recording
            recording = UIFixture.Recording(elapsed: elapsedText(elapsed), playhead: 0)
        case .analysing: phase = .analysing
        case .showingTake: phase = take == nil ? .empty : .showingTake
        }
        let voices = live.phrase.recordings
        let model = live.recording.map { recording in
            UIFixture.ModelRecording(voice: voiceTitle(recording), region: nil, attribution: attribution(recording),
                                     voices: voices.map(voiceRow))
        }
        let fixture = UIFixture(
            name: fixtureName, summary: "live", phrase: live.phrase.id.rawValue, manifest: manifest,
            sidebar: SidebarState(selectedPhraseID: live.phrase.id.rawValue,
                                  expandedPackIDs: manifest.packs.filter { !$0.isComingSoon }.map(\.id)),
            phase: phase, recording: recording, take: take?.id, savedTakes: screen.savedTakes, analysis: analysis,
            operationalError: screen.operationalError.map(operationalError),
            persistence: screen.persistence.flatMap(persistence), modelRecording: model)
        let earlier = result.map { r in screen.ghosts.map { ghost($0, axis: r.modelAxis) } } ?? []
        var loaded = LoadedFixture(fixture: fixture, phrase: phrase(live, result: result), take: take,
                                   earlierTakes: earlier)
        if let model = screen.modelSeconds { loaded.liveSeconds = (model, screen.youSeconds ?? model) }
        return loaded
    }

    /// "0:02": whole seconds.
    static func elapsedText(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

extension Verdict {
    /// Every live result is `.notScored` (spec 28): v1 shows, it never judges.
    init(notScored: Void) { self.kind = .notScored }
}
