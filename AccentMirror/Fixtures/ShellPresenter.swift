import AMCore
import AMPipeline
import Foundation

// What the shell shows for a contract state. Pure value types, no SwiftUI: the views only draw these.
// Show-don't-judge v1 (specs 28 and 29): nothing here reads a verdict, a diff row, a stress line or a measure state. An
// analysed take shows card 1 "YOUR TAKE" with the v3 result row, the strip with neutral bars and the native row's
// dictionary-stress dots, the pitch card with earlier takes, and the inspector's plain measures.

struct DetailPresentation: Sendable {
    var banner: BannerPresentation?
    var card: CardPresentation
    var strip: StripPresentation
    var pitch: PitchPresentation
    var inspector: InspectorPresentation
}

struct BannerPresentation: Sendable, Equatable {
    var icon: String
    var sentence: String
    var button: String
    var closable: Bool
}

struct CardPresentation: Sendable {
    var title: String
    var rows: [CardRow]
    /// The one quiet line (Geist 12 secondary, info.circle) under the result row; never counted as a row.
    var quietLine: Sentence?
    /// The clipped quiet line (v3.5 I4 tier B) ends with an Input… button.
    var quietLineInput = false
}

struct CardRow: Sendable {
    enum Icon: Sendable, Equatable {
        case symbol(String)
        /// The result row's 16 pt overlay glyph: two waves, one soft and one thin (v3 §3.1).
        case overlay
    }

    enum Trailing: Sendable, Equatable {
        case none
        /// The result row's Play Both ghost button (⌥⌘L).
        case playBoth
        case button(String)
        /// v3.5 I4 tier A (too loud to measure): Input…, then the row's button (Try Again).
        case inputThenButton(String)
        /// The recording row's level meter (r6 E5, v3.2 W2). nil reads the live meter, drawn only while a take feeds
        /// it; a fixture passes its frozen frame (`recording-level`, `recording-too-loud`).
        case levelMeter(LevelReading?)
    }

    var icon: Icon?
    var sentence: Sentence
    var trailing: Trailing
}

struct StripPresentation: Sendable {
    var native: [StripCluster]
    var you: YouRow
    /// Native syllable to your matching syllable; empty unless your row shows labelled bars.
    var connectors: [TimingConnector]
    /// The same syllable pairs as indices into `native` and your clusters, for the played-syllable outline (r6 E4).
    var pairs: [SyllablePair] = []

    enum YouRow: Sendable {
        /// Dashed placeholder, "Your take appears here."
        case placeholder
        /// Live bars in strip.bar, binned from the envelope stream, up to a 2 pt Lime playhead (§7, A3, r6 E9).
        case recording(envelope: RecordingEnvelope)
        /// A take problem with audio (§7.1): the take drawn as a waveform grouped by syllable, in strip.bar, no
        /// labels, shaped by the problem, with a Geist 12 secondary caption naming it when there is one.
        case takeProblem(clusters: [StripCluster], shape: TakeProblemShape, caption: String?)
        /// Bars; labels hidden for analysing and unalignable takes.
        case bars(clusters: [StripCluster], slots: [MissingSlot], showsLabels: Bool)
    }
}

/// How a take problem's audio is drawn in your row.
enum TakeProblemShape: Sendable, Equatable {
    /// Too quiet, too short, words don't match: a flat, near-silent waveform, a couple of points tall.
    case nearSilent
    /// Clipped: the waveform cut flat at the top (and, mirrored, at the bottom).
    case clipped
    /// Fallback for a problem that has no audio in practice (no speech): the take as heard, grey, unlabelled.
    case plain
}

/// One syllable's bars and label. Every bar in both rows is `strip.bar` at the recording's own envelope (v3.1 V1).
struct StripCluster: Sendable, Equatable {
    var start: Double
    var end: Double
    var prominence: Double
    var label: ClusterLabel?
    /// When a merged-word fallback label spans the whole word rather than a single cluster, this holds the word's
    /// start…end on the row's timeline; nil centres the label on this cluster's own `start...end`.
    var labelSpan: ClosedRange<Double>? = nil
    /// The Lime dictionary-stress dot under the label (native row only, v3.1 V2).
    var dot: Bool
    /// The phrase word this syllable belongs to (index into the phrase's words): clicking its label loops that word.
    /// Nil for an inserted word.
    var word: Int? = nil
    /// Stable seed so the bar texture is the same on every render.
    var seed: Int
    var tooltip: String?
}

struct ClusterLabel: Sendable, Equatable {
    enum Style: Sendable, Equatable {
        /// Native, dictionary-stressed: bold caps, primary, with the dot.
        case caps
        /// Native, the rest: lowercase, secondary.
        case lower
        /// Your row (v3.1 V3): lowercase, regular, tertiary.
        case yours
        /// A heard word, italics, secondary ("photograph" in quotes, or "+ so").
        case heard
        /// Merged-word fallback (v3.4 Y2.3): whole folded word once, lowercase, Geist 12 regular, text.tertiary.
        case merged
    }

    var text: String
    var style: Style
}

struct MissingSlot: Sendable, Equatable {
    var position: Double
    var expected: String
}

struct PitchPresentation: Sendable {
    var rangeSemitones: Double
    var band: [BandSegment]
    var you: [PitchSegment]
    /// Up to 3 earlier takes, 1 pt in pitch.you at 30/20/12%; empty when off (⇧⌘G) or when your line isn't drawn.
    var earlier: [EarlierTakeLine]
    var message: String?
    /// Native words under the baseline (model time). Target words always keep their label when the plot is
    /// narrow; the others are hidden first (fixes round 5, `LabelLayout`).
    var words: [(text: String, start: Double, end: Double, isTarget: Bool)]
    /// Native syllables, for the faint waveform texture behind the plot.
    var texture: [StripCluster]
    /// The legend's "You" item: only with a take drawn over the model. A native-only card (before the first take,
    /// recording, a take problem) shows the band swatch and "Native range" alone (v3.2 W1).
    var showsYouLegend: Bool = true
}

/// The Details inspector (v3 §4).
struct InspectorPresentation: Sendable, Equatable {
    var measures: [MeasureRow]
    var measuresNote: String?
    /// "Clear" or "Rough"; nil with nothing analysed.
    var alignment: String?
    var model: ModelRecordingPresentation?
    /// "Not saved" lines for the take.
    var takeStatus: String?

    static let empty = InspectorPresentation(measures: [], measuresNote: nil, alignment: nil, model: nil, takeStatus: nil)
}

struct ModelRecordingPresentation: Sendable, Equatable {
    /// "p311 · Iowa", or the pop-up's closed state "Iowa · p311" (r6 E7, v3.3 X2).
    var title: String
    var attribution: String
    var voices: [String]
    var selected: String
    /// Each row's "p311 · M" tag, in `voices` order; empty when the fixture gives none.
    var tags: [String] = []
    /// The checked row.
    var selectedIndex: Int?
    /// Drawn open (fixture only: a real menu can't be held open for a screenshot).
    var isOpen = false
}

@MainActor
enum ShellPresenter {
    // MARK: Toolbar

    static func toolbar(for loaded: LoadedFixture) -> ToolbarState {
        let fixture = loaded.fixture
        let take = loaded.take
        let problem = firstTakeProblem(loaded)
        let isRecording = fixture.phase == .recording

        let record: ToolbarState.RecordButton =
            isRecording ? .stop : .record(enabled: problem != .noMicrophone)

        var youEnabled = false
        if fixture.phase == .showingTake || fixture.phase == .analysing, let take { youEnabled = take.hasAudio }
        if isRecording { youEnabled = false }

        let takeMenu: ToolbarState.TakeMenuLabel
        if fixture.phase == .showingTake, let take, take.hasAudio, problem != nil {
            // A take problem is never saved and never counts as a take (§7): with audio, You plays the last
            // try, so the menu names it whatever the take file says (A7).
            takeMenu = .lastTryNotSaved
        } else if fixture.phase == .showingTake, let number = take?.number {
            takeMenu = .take(number)
        } else if let latest = fixture.savedTakes.first {
            takeMenu = .take(latest)
        } else {
            takeMenu = .takes
        }

        return ToolbarState(
            title: loaded.phrase.text,
            subtitle: isRecording ? .recording(elapsed: fixture.recording?.elapsed ?? "0:00") : .source(fixture.subtitle ?? loaded.phrase.subtitle),
            modelEnabled: !isRecording,
            youEnabled: youEnabled,
            record: record,
            takeMenu: takeMenu,
            takeMenuNote: take?.alignment == .unalignable && fixture.phase == .showingTake ? Copy.notComparable : nil,
            savedTakes: fixture.savedTakes
        )
    }

    // MARK: Detail

    static func detail(for loaded: LoadedFixture, showEarlierTakes: Bool = true) -> DetailPresentation {
        DetailPresentation(
            banner: banner(loaded.fixture),
            card: card(loaded),
            strip: strip(loaded),
            pitch: pitch(loaded, showEarlierTakes: showEarlierTakes),
            inspector: inspector(loaded)
        )
    }

    /// An operational error wins over the save notice; savedPruneFailed and cancelled show nothing (§13.2).
    static func banner(_ fixture: UIFixture) -> BannerPresentation? {
        if let error = fixture.operationalError {
            let copy = Copy.banner(error)
            return BannerPresentation(icon: "exclamationmark.bubble", sentence: copy.sentence, button: copy.button, closable: false)
        }
        if fixture.persistence == .saveFailed {
            return BannerPresentation(
                icon: "externaldrive.badge.exclamationmark", sentence: Copy.saveFailed,
                button: Copy.saveFailedButton, closable: true
            )
        }
        return nil
    }

    /// Only the first take problem in plan order, and never alongside an operational banner.
    static func firstTakeProblem(_ loaded: LoadedFixture) -> TakeProblem? {
        guard loaded.fixture.operationalError == nil, loaded.fixture.phase == .showingTake,
              let problems = loaded.fixture.analysis?.takeProblems
        else { return nil }
        return TakeProblem.allCases.first(where: problems.contains)
    }

    /// A take drawn over the model: analysed, aligned, no take problem, no app problem.
    static func isResult(_ loaded: LoadedFixture) -> Bool {
        loaded.fixture.phase == .showingTake && loaded.fixture.operationalError == nil
            && loaded.fixture.analysis != nil && loaded.take?.alignment == .aligned && loaded.take?.hasAudio == true
            && firstTakeProblem(loaded) == nil
    }

    // MARK: Card 1 (v3 §3.1)

    static func card(_ loaded: LoadedFixture) -> CardPresentation {
        let fixture = loaded.fixture
        switch fixture.phase {
        case .empty:
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: .symbol("mic"), sentence: [.plain(Copy.emptyPrompt)], trailing: .none),
            ])
        case .recording:
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: .symbol("mic.fill"), sentence: [.plain(Copy.recordingPrompt)], trailing: .levelMeter(fixture.recording?.level)),
            ])
        case .analysing:
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: nil, sentence: [.plain(Copy.analysing)], trailing: .none),
            ])
        case .showingTake:
            break
        }

        if loaded.take?.alignment == .unalignable {
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: .symbol("text.badge.minus"), sentence: [.plain(Copy.unalignable)], trailing: .none),
            ])
        }

        if let problem = firstTakeProblem(loaded) {
            // The too-quiet icon is text.secondary like every other card 1 icon (v3 §5).
            let button = Copy.takeProblemButton(problem)
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(
                    icon: .symbol(takeProblemIcon(problem)),
                    sentence: [.plain(Copy.takeProblem(problem))],
                    trailing: problem == .clipped
                        ? button.map(CardRow.Trailing.inputThenButton) ?? .none
                        : button.map(CardRow.Trailing.button) ?? .none
                ),
            ])
        }

        guard let analysis = fixture.analysis, fixture.operationalError == nil else {
            // An operational error with nothing shown keeps the empty state.
            return card(LoadedFixture(fixture: with(fixture) { $0.phase = .empty }, phrase: loaded.phrase, take: nil))
        }
        let quiet = quietLine(analysis, take: loaded.take)
        return CardPresentation(title: Copy.yourTake, rows: [
            CardRow(icon: .overlay, sentence: [.plain(Copy.resultRow)], trailing: .playBoth),
        ], quietLine: quiet.map(Copy.quietLine), quietLineInput: quiet == .clipped)
    }

    /// Clipping (v3.5 I4 tier B), then coverage, then timing, then insertions; the coverage floor is the decision
    /// procedure's own threshold.
    static func quietLine(_ analysis: Analysis, take: TakeFixture?) -> ResultQuietLine? {
        ResultQuietLine.first(
            clipped: analysis.clipped ?? false,
            comparableCoverage: analysis.comparableCoverage,
            minimumCoverage: Thresholds.current.decision.minComparableCoverage,
            timing: analysis.timing,
            insertions: ResultQuietLine.insertedWords(take)
        )
    }

    static func takeProblemIcon(_ problem: TakeProblem) -> String {
        switch problem {
        case .noMicrophone, .micDenied: "mic.slash"
        case .noSpeech: "waveform.slash"
        case .tooShort: "timer"
        case .tooQuiet: "speaker.wave.1"
        case .clipped: "speaker.wave.3"
        case .wordsDontMatch: "text.badge.xmark"
        }
    }

    // MARK: Strip (v3 §3.2, v3.1 V1–V3)

    static func nativeClusters(_ phrase: PhraseFixture) -> [StripCluster] {
        var seed = 1
        return phrase.words.enumerated().flatMap { wordIndex, word in
            let dotted = StressMarks.dottedSyllable(word)
            let ambiguous = StressMarks.isAmbiguous(word)
            let isMerged = !word.syllables.isEmpty
                && word.syllables.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            let wordSpan: ClosedRange<Double>? = isMerged
                ? (word.syllables.first!.start...word.syllables.last!.end)
                : nil
            let folded = isMerged ? DisplayWord.fold(word.text) : ""
            return word.syllables.enumerated().map { index, syllable in
                seed += 1
                let isDotted = dotted == index
                let label: ClusterLabel? = if isMerged {
                    (index == 0 && !folded.isEmpty) ? ClusterLabel(text: folded, style: .merged) : nil
                } else {
                    ClusterLabel(
                        text: isDotted ? syllable.text.uppercased() : syllable.text.lowercased(),
                        style: isDotted ? .caps : .lower
                    )
                }
                return StripCluster(
                    start: syllable.start, end: syllable.end, prominence: syllable.prominence,
                    label: label,
                    labelSpan: (isMerged && index == 0) ? wordSpan : nil,
                    dot: isDotted,
                    word: wordIndex,
                    seed: seed,
                    tooltip: ambiguous ? Copy.ambiguousTooltip : nil
                )
            }
        }
    }

    /// Your row: neutral bars and lowercase tertiary labels (v3.1 V3); heard words in italics; missing words as slots.
    static func yourClusters(_ take: TakeFixture, labelled: Bool, phrase: PhraseFixture? = nil)
        -> (clusters: [StripCluster], slots: [MissingSlot]) {
        var clusters: [StripCluster] = []
        var slots: [MissingSlot] = []
        var seed = 101
        let words = phrase.map { TimingConnectors.nativeWordIndices(phrase: $0, take: take) }
            ?? Array(repeating: nil, count: take.words.count)
        for (pair, wordIndex) in zip(take.words, words) {
            switch pair.kind {
            case .missing:
                if let position = pair.slot { slots.append(MissingSlot(position: position, expected: pair.expected ?? "")) }
            case .present:
                let isMerged = !pair.syllables.isEmpty
                    && pair.syllables.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                let wordSpan: ClosedRange<Double>? = isMerged
                    ? (pair.syllables.first!.start...pair.syllables.last!.end)
                    : nil
                let rawWord = pair.expected
                    ?? wordIndex.flatMap { phrase?.words.indices.contains($0) == true ? phrase?.words[$0].text : nil }
                    ?? ""
                let folded = isMerged ? DisplayWord.fold(rawWord) : ""
                for (index, syllable) in pair.syllables.enumerated() {
                    seed += 1
                    let label: ClusterLabel? = if isMerged {
                        (index == 0 && !folded.isEmpty) ? ClusterLabel(text: folded, style: .merged) : nil
                    } else {
                        ClusterLabel(text: syllable.text.lowercased(), style: .yours)
                    }
                    clusters.append(StripCluster(
                        start: syllable.start, end: syllable.end, prominence: syllable.prominence,
                        label: label,
                        labelSpan: (isMerged && index == 0) ? wordSpan : nil,
                        dot: false, word: wordIndex, seed: seed, tooltip: nil
                    ))
                }
            case .substituted, .inserted:
                // One italic label for the heard word, on its middle syllable.
                let heard = pair.heard ?? ""
                let label = pair.kind == .inserted ? "+ \(heard)" : "\u{201C}\(heard)\u{201D}"
                let tooltip = pair.kind == .substituted ? Copy.substitutedTooltip(heard: heard) : nil
                for (index, syllable) in pair.syllables.enumerated() {
                    seed += 1
                    clusters.append(StripCluster(
                        start: syllable.start, end: syllable.end, prominence: syllable.prominence,
                        label: index == pair.syllables.count / 2 ? ClusterLabel(text: label, style: .heard) : nil,
                        dot: false, word: wordIndex, seed: seed, tooltip: tooltip
                    ))
                }
            }
        }
        if !labelled {
            clusters = clusters.map { var c = $0; c.label = nil; c.labelSpan = nil; c.tooltip = nil; return c }
        }
        return (clusters, slots)
    }

    static func strip(_ loaded: LoadedFixture) -> StripPresentation {
        let native = nativeClusters(loaded.phrase)
        let fixture = loaded.fixture
        let you: StripPresentation.YouRow
        var connectors: [TimingConnector] = []
        var pairs: [SyllablePair] = []
        switch fixture.phase {
        case .empty:
            you = .placeholder
        case .recording:
            you = .recording(envelope: recordingEnvelope(loaded))
        case .analysing:
            let parts = loaded.take.map { yourClusters($0, labelled: false) }
            you = .bars(clusters: parts?.clusters ?? [], slots: [], showsLabels: false)
        case .showingTake:
            guard let take = loaded.take else { you = .placeholder; break }
            if !take.hasAudio {
                // No microphone, mic denied, no speech: nothing was recorded.
                you = .placeholder
            } else if take.alignment == .unalignable {
                you = .bars(clusters: yourClusters(take, labelled: false).clusters, slots: [], showsLabels: false)
            } else if let problem = firstTakeProblem(loaded) {
                you = .takeProblem(
                    clusters: yourClusters(take, labelled: false).clusters,
                    shape: takeProblemShape(problem),
                    caption: Copy.takeProblemCaption(problem)
                )
            } else if fixture.analysis == nil {
                you = .placeholder
            } else {
                let parts = yourClusters(take, labelled: true, phrase: loaded.phrase)
                you = .bars(clusters: parts.clusters, slots: parts.slots, showsLabels: true)
                connectors = TimingConnectors.connectors(phrase: loaded.phrase, take: take)
                pairs = syllablePairs(phrase: loaded.phrase, take: take)
            }
        }
        return StripPresentation(native: native, you: you, connectors: connectors, pairs: pairs)
    }

    /// The recording's envelope stream. Fixtures synthesise it from the take's syllables: `recording.seconds` of
    /// audio, or the old `playhead` fraction of the model's duration.
    static func recordingEnvelope(_ loaded: LoadedFixture) -> RecordingEnvelope {
        let seconds = playbackSeconds(loaded)
        let recording = loaded.fixture.recording
        let elapsed = recording?.seconds ?? (recording?.playhead ?? 0) * seconds.model
        let syllables = loaded.take.map { yourClusters($0, labelled: false).clusters } ?? []
        return .synthetic(syllables: syllables, takeSeconds: seconds.you, elapsed: elapsed)
    }

    /// Native syllable to your matching syllable, as indices into the strip's two cluster lists, in the same walk as
    /// the connectors: words in alignment order, then syllables by index within each word.
    static func syllablePairs(phrase: PhraseFixture, take: TakeFixture) -> [SyllablePair] {
        var starts: [Int] = []
        var total = 0
        for word in phrase.words {
            starts.append(total)
            total += word.syllables.count
        }
        var out: [SyllablePair] = []
        var nativeWord = 0
        var yourOffset = 0
        for pair in take.words {
            switch pair.kind {
            case .missing:
                nativeWord += 1
            case .inserted:
                yourOffset += pair.syllables.count
            case .present, .substituted:
                guard phrase.words.indices.contains(nativeWord) else { return out }
                let count = min(phrase.words[nativeWord].syllables.count, pair.syllables.count)
                for index in 0..<count {
                    out.append(SyllablePair(native: starts[nativeWord] + index, you: yourOffset + index))
                }
                yourOffset += pair.syllables.count
                nativeWord += 1
            }
        }
        return out
    }

    /// Too short and words don't match use the too-quiet treatment (Designer answer 3, round 3).
    static func takeProblemShape(_ problem: TakeProblem) -> TakeProblemShape {
        switch problem {
        case .tooQuiet, .tooShort, .wordsDontMatch: .nearSilent
        case .clipped: .clipped
        case .noMicrophone, .micDenied, .noSpeech: .plain
        }
    }

    // MARK: Pitch (v3 §3.3, v3.1 V4–V5)

    /// The manifest's `targets` for this phrase, normalised.
    static func namedTargetWords(_ loaded: LoadedFixture) -> Set<String> {
        let manifest = loaded.fixture.manifest ?? .stub
        let targets = manifest.packs.flatMap(\.phrases).first { $0.id == loaded.phrase.id }?.targets ?? []
        return Set(targets.map(normalizedWord)).intersection(Set(loaded.phrase.words.map { normalizedWord($0.text) }))
    }

    /// A target word under the pitch plot (Addendum r4 C6, v3 §11): one with a dictionary-stressed syllable, or one
    /// named in the manifest. Its label always shows; the others give way first when the plot is narrow.
    static func isTargetWord(_ word: NativeWord, named: Set<String>) -> Bool {
        StressMarks.dottedSyllable(word) != nil || named.contains(normalizedWord(word.text))
    }

    static func normalizedWord(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    static func pitch(_ loaded: LoadedFixture, showEarlierTakes: Bool = true) -> PitchPresentation {
        let phrase = loaded.phrase
        var you: [PitchSegment] = []
        var earlier: [EarlierTakeLine] = []
        var message: String?
        if isResult(loaded), let take = loaded.take {
            // A stretch shorter than 3 frames isn't drawn (§13.7).
            you = take.pitch.filter { $0.points.count >= 3 }
            if you.isEmpty { message = Copy.noPitch }
            earlier = EarlierTakes.lines(loaded.earlierTakes,
                                         visible: loaded.fixture.earlierTakesVisible ?? showEarlierTakes)
        }
        let named = namedTargetWords(loaded)
        return PitchPresentation(
            rangeSemitones: phrase.rangeSemitones,
            band: phrase.band,
            you: you,
            earlier: earlier,
            message: message,
            words: phrase.words.map { word in
                (text: word.text, start: word.start, end: word.end, isTarget: isTargetWord(word, named: named))
            },
            texture: nativeClusters(phrase),
            showsYouLegend: isResult(loaded)
        )
    }

    // MARK: Playback

    /// Seconds to play for each side: the fixture's own, else the described lengths, else a nominal phrase.
    static func playbackSeconds(_ loaded: LoadedFixture) -> (model: Double, you: Double) {
        if let live = loaded.liveSeconds { return live }
        if let frame = loaded.fixture.playBoth { return (frame.modelSeconds, frame.youSeconds) }
        let describe = loaded.fixture.analysis?.describe
        let model = describe?.native.lengthSeconds.min ?? nominalPhraseSeconds
        let you = describe?.you.lengthSeconds.value ?? nominalPhraseSeconds
        return (model, you)
    }

    /// Clicking a word's label (v3 §3.5): the model's slice of that word, 0.4 s, then yours, looping until Esc. A
    /// missing word loops the model only. Returns the schedule and the word as the caption names it.
    static func loopSchedule(_ loaded: LoadedFixture, word index: Int) -> (schedule: PlaybackSchedule, word: String)? {
        guard loaded.phrase.words.indices.contains(index) else { return nil }
        let word = loaded.phrase.words[index]
        guard let first = word.syllables.first, let last = word.syllables.last else { return nil }
        let seconds = playbackSeconds(loaded)
        let model = (from: first.start, to: last.end, seconds: (last.end - first.start) * seconds.model)
        guard isResult(loaded), let take = loaded.take else {
            // No analysed take on screen (v3.2 W1: before the first take, while recording, on a take problem):
            // the model's slice only, with no pause and no You half.
            return (.loopModel(model), normalizedWord(word.text))
        }
        let indices = TimingConnectors.nativeWordIndices(phrase: loaded.phrase, take: take)
        var you: (from: Double, to: Double, seconds: Double)?
        if let pairIndex = indices.firstIndex(of: index), take.words[pairIndex].kind != .missing,
           let a = take.words[pairIndex].syllables.first, let b = take.words[pairIndex].syllables.last {
            you = (from: a.start, to: b.end, seconds: (b.end - a.start) * seconds.you)
        }
        return (.loop(model: model, you: you), normalizedWord(word.text))
    }

    /// Fixture-only stand-in for a clip's length until spec 21 plays real audio.
    static let nominalPhraseSeconds = 2.0

    // MARK: Inspector (v3 §4, v3.1 V4)

    static func inspector(_ loaded: LoadedFixture) -> InspectorPresentation {
        var result = InspectorPresentation.empty
        let fixture = loaded.fixture
        if isResult(loaded), let analysis = fixture.analysis {
            if let describe = analysis.describe {
                result.measures = ThisTake.rows(describe)
                result.measuresNote = ThisTake.note(describe)
            }
            result.alignment = analysis.timing.map(ThisTake.alignment)
        } else if fixture.phase != .showingTake, fixture.operationalError == nil,
                  let describe = fixture.analysis?.describe {
            // No take of yours on screen (v3.2 W1): NATIVE RANGE still shows, display-only; You is an em dash and
            // there's no ALIGNMENT (nothing was aligned).
            result.measures = ThisTake.rows(describe).map {
                var row = $0
                row.you = ThisTake.missing
                row.youTooltip = nil
                return row
            }
            result.measuresNote = ThisTake.note(describe)
        }
        if let model = fixture.modelRecording {
            result.model = ModelRecordingPresentation(
                title: [model.voice, model.region].compactMap { $0 }.joined(separator: " \u{00B7} "),
                attribution: model.attribution, voices: model.voices, selected: model.voice,
                tags: model.tags ?? [], selectedIndex: model.selected, isOpen: model.open ?? false
            )
        }
        if fixture.phase == .showingTake, let take = loaded.take {
            let status = fixture.persistence ?? (take.number == nil ? .notSaved : .saved)
            result.takeStatus = Copy.persistence(status)
        }
        return result
    }

    private static func with<T>(_ value: T, _ change: (inout T) -> Void) -> T {
        var copy = value
        change(&copy)
        return copy
    }
}
