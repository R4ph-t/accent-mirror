import Foundation

// What the shell shows for a contract state. Pure value types, no SwiftUI: the views only draw these.

struct DetailPresentation: Sendable {
    var banner: BannerPresentation?
    var card: CardPresentation
    var strip: StripPresentation
    var pitch: PitchPresentation
    var inspector: [InspectorSection]
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
    /// Geist 12 secondary lines with info.circle, under the rows; they don't count toward the 3 rows.
    var infoLines: [Sentence]
}

struct CardRow: Sendable {
    enum Trailing: Sendable, Equatable {
        case none
        /// Plays the model then you for that word (visual only in this shell).
        case play
        case button(String)
    }

    var icon: String?
    /// The too-quiet icon is mistake blue (§11.1); every other card 1 icon is secondary.
    var iconIsMistake: Bool
    var sentence: Sentence
    var trailing: Trailing
}

struct StripPresentation: Sendable {
    var native: [StripCluster]
    var you: YouRow

    enum YouRow: Sendable {
        /// Dashed placeholder, "Your take appears here."
        case placeholder
        /// Live bars in strip.bar up to a 2 pt Lime playhead.
        case recording(clusters: [StripCluster], playhead: Double)
        /// A take problem with audio (§7.1): the take drawn as a waveform grouped by syllable, in strip.bar, no
        /// labels, no Lime, shaped by the problem, with a Geist 12 secondary caption naming it when there is one.
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

struct StripCluster: Sendable, Equatable {
    /// Bar colour role. Stressed bars are Lime; your other bars are darker than the native row's (Designer
    /// review of PR #4, fix 3), except heard-only words, take problems and in-flight takes, which stay strip.bar.
    enum Fill: Sendable, Equatable {
        /// Measured as stressed: the vertical Lime bar gradient.
        case stressed
        /// strip.bar: the native row, and your grey bars (recording, analysing, unalignable, inserted,
        /// substituted, take problems).
        case neutral
        /// strip.you: your unstressed bars in a result.
        case yours
    }

    var start: Double
    var end: Double
    var prominence: Double
    var fill: Fill
    var label: ClusterLabel?
    /// Stable seed so the bar texture is the same on every render.
    var seed: Int
    var tooltip: String?
}

/// A syllable of your take, by word and index within the word.
struct FlaggedSyllable: Hashable, Sendable {
    var word: String
    var index: Int
}

struct ClusterLabel: Sendable, Equatable {
    enum Style: Sendable, Equatable {
        /// Bold caps, primary.
        case caps
        /// Lowercase, secondary.
        case lower
        /// Blue caps, triangle, dotted underline.
        case mistake
        /// A heard word, italics, secondary ("photograph" in quotes, or "+ so").
        case heard
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
    var message: String?
    /// Native words under the baseline (model time).
    var words: [(text: String, start: Double, end: Double)]
    /// Lime marks on the baseline: the native's stressed syllables.
    var stressedSpans: [(start: Double, end: Double)]
    /// Native syllables, for the faint waveform texture behind the plot.
    var texture: [StripCluster]
}

struct InspectorSection: Sendable, Equatable {
    var title: String
    var lines: [String]
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
            subtitle: isRecording ? .recording(elapsed: fixture.recording?.elapsed ?? "0:00") : .source(loaded.phrase.subtitle),
            modelEnabled: !isRecording,
            youEnabled: youEnabled,
            record: record,
            takeMenu: takeMenu,
            takeMenuNote: take?.alignment == .unalignable && fixture.phase == .showingTake ? Copy.notComparable : nil,
            savedTakes: fixture.savedTakes
        )
    }

    // MARK: Detail

    static func detail(for loaded: LoadedFixture) -> DetailPresentation {
        DetailPresentation(
            banner: banner(loaded.fixture),
            card: card(loaded),
            strip: strip(loaded),
            pitch: pitch(loaded),
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

    static func card(_ loaded: LoadedFixture) -> CardPresentation {
        let fixture = loaded.fixture
        switch fixture.phase {
        case .empty:
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: "mic", iconIsMistake: false, sentence: [.plain(Copy.emptyPrompt)], trailing: .none),
            ], infoLines: [])
        case .recording:
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: "mic.fill", iconIsMistake: false, sentence: [.plain(Copy.recordingPrompt)], trailing: .none),
            ], infoLines: [])
        case .analysing:
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: nil, iconIsMistake: false, sentence: [.plain(Copy.analysing)], trailing: .none),
            ], infoLines: [])
        case .showingTake:
            break
        }

        if loaded.take?.alignment == .unalignable {
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(icon: "text.badge.minus", iconIsMistake: false, sentence: [.plain(Copy.unalignable)], trailing: .none),
            ], infoLines: [])
        }

        if let problem = firstTakeProblem(loaded) {
            return CardPresentation(title: Copy.yourTake, rows: [
                CardRow(
                    icon: takeProblemIcon(problem), iconIsMistake: problem == .tooQuiet,
                    sentence: [.plain(Copy.takeProblem(problem))],
                    trailing: Copy.takeProblemButton(problem).map(CardRow.Trailing.button) ?? .none
                ),
            ], infoLines: [])
        }

        guard let analysis = fixture.analysis, let verdict = analysis.verdict else {
            // An operational error with nothing analysed keeps the empty state.
            return card(LoadedFixture(fixture: with(fixture) { $0.phase = .empty }, phrase: loaded.phrase, take: nil))
        }

        let measures = analysis.measures ?? []
        var rows: [CardRow] = []
        switch verdict.kind {
        case .feedback:
            rows = orderedRows(verdict.rows ?? []).map { row in
                CardRow(icon: diffIcon(row.kind), iconIsMistake: false, sentence: Copy.row(row), trailing: .play)
            }
        case .close:
            rows = [CardRow(icon: "checkmark.circle", iconIsMistake: false, sentence: Copy.close(measures: measures), trailing: .none)]
        case .noClearDifference:
            rows = [CardRow(
                icon: "equal.circle", iconIsMistake: false,
                sentence: Copy.noClearDifference(verdict.reasons ?? []), trailing: .none
            )]
        case .inconclusive:
            if let value = verdict.inconclusive {
                rows = [CardRow(
                    icon: "questionmark.circle", iconIsMistake: false, sentence: Copy.inconclusive(value),
                    trailing: Copy.inconclusiveHasTryAgain(value) ? .button("Try Again") : .none
                )]
            }
        }

        var info: [Sentence] = []
        if let quiet = Copy.quietLines(analysis.notes).first { info.append(quiet) }
        if let placementOnly = Copy.placementOnlyLine(measures) { info.append(placementOnly) }
        return CardPresentation(title: Copy.whatToChange, rows: rows, infoLines: info)
    }

    /// §10 order, rough timing first, at most 3 rows; too much contrast only fits when there is room.
    static func orderedRows(_ rows: [DiffRow]) -> [DiffRow] {
        let order = DiffRow.Kind.allCases
        let sorted = rows.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
        return Array(sorted.prefix(3))
    }

    static func diffIcon(_ kind: DiffRow.Kind) -> String {
        switch kind {
        case .roughTiming: "waveform.path.ecg"
        case .placement: "arrow.left.arrow.right"
        case .contrast: "chart.bar"
        case .reduction: "arrow.left.and.right"
        case .range: "arrow.up.and.down"
        case .finalDirection: "arrow.down.right"
        case .tooMuchContrast: "chart.bar.fill"
        }
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

    // MARK: Strip

    static func nativeClusters(_ phrase: PhraseFixture) -> [StripCluster] {
        var seed = 1
        return phrase.words.flatMap { word in
            let unchecked = word.stressCheck == .expectedAmbiguous || word.stressCheck == .referenceAnomaly
            return word.syllables.map { syllable in
                seed += 1
                return StripCluster(
                    start: syllable.start, end: syllable.end, prominence: syllable.prominence,
                    fill: syllable.stressed ? .stressed : .neutral,
                    label: ClusterLabel(
                        text: unchecked || syllable.label == .lower ? syllable.text.lowercased() : syllable.text.uppercased(),
                        style: unchecked || syllable.label == .lower ? .lower : .caps
                    ),
                    seed: seed,
                    tooltip: unchecked ? Copy.ambiguousTooltip : nil
                )
            }
        }
    }

    /// Your row. `flagged` holds the only syllables that may carry the mistake marker (see `flaggedSyllables`);
    /// any other `mistake` label in the take is drawn as a plain lowercase label.
    static func yourClusters(_ take: TakeFixture, allGrey: Bool, flagged: Set<FlaggedSyllable> = [])
        -> (clusters: [StripCluster], slots: [MissingSlot]) {
        var clusters: [StripCluster] = []
        var slots: [MissingSlot] = []
        var seed = 101
        for pair in take.words {
            switch pair.kind {
            case .missing:
                if let position = pair.slot { slots.append(MissingSlot(position: position, expected: pair.expected ?? "")) }
            case .present:
                let unchecked = pair.stressCheck == .expectedAmbiguous || pair.stressCheck == .referenceAnomaly
                let word = (pair.expected ?? pair.heard ?? "").lowercased()
                for (index, syllable) in pair.syllables.enumerated() {
                    seed += 1
                    let style: ClusterLabel.Style
                    if unchecked { style = .lower } else {
                        switch syllable.label {
                        case .caps: style = .caps
                        case .lower: style = .lower
                        case .mistake:
                            style = flagged.contains(FlaggedSyllable(word: word, index: index)) ? .mistake : .lower
                        }
                    }
                    clusters.append(StripCluster(
                        start: syllable.start, end: syllable.end, prominence: syllable.prominence,
                        fill: syllable.stressed ? .stressed : .yours,
                        label: ClusterLabel(text: style == .lower ? syllable.text.lowercased() : syllable.text.uppercased(), style: style),
                        seed: seed, tooltip: unchecked ? Copy.ambiguousTooltip : nil
                    ))
                }
            case .substituted, .inserted:
                // Grey bars (never Lime, no stress comparison) and one italic label for the heard word.
                let heard = pair.heard ?? ""
                let label = pair.kind == .inserted ? "+ \(heard)" : "\u{201C}\(heard)\u{201D}"
                let tooltip = pair.kind == .substituted ? Copy.substitutedTooltip(heard: heard, expected: pair.expected ?? "") : nil
                for (index, syllable) in pair.syllables.enumerated() {
                    seed += 1
                    let isMiddle = index == pair.syllables.count / 2
                    clusters.append(StripCluster(
                        start: syllable.start, end: syllable.end, prominence: syllable.prominence, fill: .neutral,
                        label: isMiddle ? ClusterLabel(text: label, style: .heard) : nil,
                        seed: seed, tooltip: tooltip
                    ))
                }
            }
        }
        if allGrey {
            clusters = clusters.map { var c = $0; c.label = nil; c.fill = .neutral; return c }
        }
        return (clusters, slots)
    }

    static func strip(_ loaded: LoadedFixture) -> StripPresentation {
        let native = nativeClusters(loaded.phrase)
        let fixture = loaded.fixture
        let you: StripPresentation.YouRow
        switch fixture.phase {
        case .empty:
            you = .placeholder
        case .recording:
            let clusters = loaded.take.map { yourClusters($0, allGrey: true).clusters } ?? []
            you = .recording(clusters: clusters, playhead: fixture.recording?.playhead ?? 0)
        case .analysing:
            let parts = loaded.take.map { yourClusters($0, allGrey: true) }
            you = .bars(clusters: parts?.clusters ?? [], slots: [], showsLabels: false)
        case .showingTake:
            guard let take = loaded.take else { you = .placeholder; break }
            if !take.hasAudio {
                // No microphone, mic denied, no speech: nothing was recorded.
                you = .placeholder
            } else if take.alignment == .unalignable {
                you = .bars(clusters: yourClusters(take, allGrey: true).clusters, slots: [], showsLabels: false)
            } else if let problem = firstTakeProblem(loaded) {
                you = .takeProblem(
                    clusters: yourClusters(take, allGrey: true).clusters,
                    shape: takeProblemShape(problem),
                    caption: Copy.takeProblemCaption(problem)
                )
            } else if fixture.analysis?.verdict == nil {
                you = .placeholder
            } else {
                let parts = yourClusters(take, allGrey: false, flagged: flaggedSyllables(fixture.analysis))
                you = .bars(clusters: parts.clusters, slots: parts.slots, showsLabels: true)
            }
        }
        return StripPresentation(native: native, you: you)
    }

    /// Too short and words don't match use the too-quiet treatment (Designer answer 3, round 3).
    static func takeProblemShape(_ problem: TakeProblem) -> TakeProblemShape {
        switch problem {
        case .tooQuiet, .tooShort, .wordsDontMatch: .nearSilent
        case .clipped: .clipped
        case .noMicrophone, .micDenied, .noSpeech: .plain
        }
    }

    /// The mistake marker goes only on the syllable named after "not" in a placement row that card 1 shows:
    /// your stress is outside the accepted set at high confidence (§8, §13 item 5). Every other verdict
    /// (close, noClearDifference, inconclusive, feedback without that row) shows no marker.
    static func flaggedSyllables(_ analysis: Analysis?) -> Set<FlaggedSyllable> {
        guard let verdict = analysis?.verdict, verdict.kind == .feedback else { return [] }
        return Set(orderedRows(verdict.rows ?? []).compactMap { row in
            guard row.kind == .placement, let word = row.word, let heard = row.heardIndex else { return nil }
            return FlaggedSyllable(word: word.lowercased(), index: heard)
        })
    }

    // MARK: Pitch

    static func pitch(_ loaded: LoadedFixture) -> PitchPresentation {
        let phrase = loaded.phrase
        var you: [PitchSegment] = []
        var message: String?
        let showsYou = loaded.fixture.phase == .showingTake && loaded.take?.alignment == .aligned
            && firstTakeProblem(loaded) == nil && loaded.fixture.analysis?.verdict != nil
        if showsYou, let take = loaded.take {
            // A stretch shorter than 3 frames isn't drawn (§13.7).
            you = take.pitch.filter { $0.points.count >= 3 }
            if you.isEmpty { message = Copy.noPitch }
        }
        let stressed = phrase.words.flatMap(\.syllables).filter(\.stressed).map { (start: $0.start, end: $0.end) }
        return PitchPresentation(
            rangeSemitones: phrase.rangeSemitones,
            band: phrase.band,
            you: you,
            message: message,
            words: phrase.words.map { (text: $0.text, start: $0.start, end: $0.end) },
            stressedSpans: stressed,
            texture: nativeClusters(phrase)
        )
    }

    // MARK: Inspector (§14)

    static func inspector(_ loaded: LoadedFixture) -> [InspectorSection] {
        var sections: [InspectorSection] = []
        let analysis = loaded.fixture.analysis
        if let measures = analysis?.measures, !measures.isEmpty {
            sections.append(InspectorSection(
                title: "MEASURES",
                lines: measures.map { "\(Copy.measureName($0.measure)): \(Copy.measureValue($0))" }
            ))
        }
        if let lines = analysis?.stress?.compactMap(Copy.stressLine), !lines.isEmpty {
            sections.append(InspectorSection(title: "STRESS", lines: lines))
        }
        if analysis?.verdict?.kind == .noClearDifference, let reasons = analysis?.verdict?.reasons {
            let ordered = NoClearDifferenceReason.allCases.filter(reasons.contains)
            sections.append(InspectorSection(title: "NO CLEAR DIFFERENCE", lines: ordered.map(Copy.noClearDifferenceReasonName)))
        }
        let quiet = Copy.quietLines(analysis?.notes).map(\.plain)
        if !quiet.isEmpty {
            sections.append(InspectorSection(title: "NOTES", lines: quiet))
        }
        if loaded.fixture.phase == .showingTake, let take = loaded.take {
            let status = loaded.fixture.persistence ?? (take.number == nil ? .notSaved : .saved)
            if let line = Copy.persistence(status) {
                sections.append(InspectorSection(title: "TAKE", lines: [line]))
            }
        }
        return sections
    }

    private static func with<T>(_ value: T, _ change: (inout T) -> Void) -> T {
        var copy = value
        change(&copy)
        return copy
    }
}
