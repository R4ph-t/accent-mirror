import Foundation

/// A run of sentence text with its styling role. Views map roles to tokens; tests read `plain`.
struct Segment: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case plain
        /// A heard word (insertions, substitutions): italics.
        case heard
    }

    var text: String
    var role: Role

    static func plain(_ text: String) -> Segment { Segment(text: text, role: .plain) }
    static func heard(_ text: String) -> Segment { Segment(text: text, role: .heard) }
}

typealias Sentence = [Segment]

extension Array where Element == Segment {
    var plain: String { map(\.text).joined() }
}

/// Every user-facing sentence of the fixture-driven shell: Designer spec v2 §11.1 and §13 where v3 keeps them, and
/// v3 §5 / v3.1 word for word. Pure functions of contract values. Show, don't judge: no string here (or in any view)
/// may use a word from `AccentMirrorTests/BannedWordTests.swift`'s list.
enum Copy {
    // MARK: Card 1 titles

    static let yourTake = "YOUR TAKE"

    // MARK: Phases (§7)

    static let emptyPrompt = "Listen to the model, then press Space to record your take."
    static let recordingPrompt = "Recording. Press Space when you\u{2019}re done."
    static let analysing = "Analysing your take\u{2026}"
    static let yourTakeAppearsHere = "Your take appears here."
    static let tooQuietToMeasure = "Too quiet to measure"
    static let tooLoudToMeasure = "Too loud to measure"
    static let tooShortToMeasure = "Too short to measure"
    static let wordsDidntMatch = "Words didn't match the phrase"
    static let noPitch = "No pitch to show for this take"
    static let unalignable = "This take was recorded for the old wording, so it can't be lined up with the new one."
    static let notComparable = "NOT COMPARABLE"
    static let notComparableTooltip = "Recorded for the old wording, so it can't be lined up with the new one."

    // MARK: Result (v3 §3.1)

    static let resultRow = "Your take is drawn over the model\u{2019}s. Play them back to back, then try another take."
    static let playBoth = "Play Both"
    static let playBothTooltip = "Play the model, then your take"
    /// VoiceOver, once a result is on screen.
    static let resultReady = "Result ready. Your take is drawn over the model\u{2019}s."

    /// Card 1's one quiet line.
    static func quietLine(_ line: ResultQuietLine) -> Sentence {
        switch line {
        case .clipped:
            return [.plain("Your take clipped. Lower the input volume and try another take.")]
        case .lowCoverage:
            return [.plain("Only part of your take lined up with the model, so some of it isn\u{2019}t drawn.")]
        case .roughTiming:
            return [.plain("The timing match is rough, so syllables may not line up exactly.")]
        case .insertions(let words):
            var line: Sentence = [.plain("You added ")]
            for (index, word) in words.enumerated() {
                if index > 0 { line.append(.plain(index == words.count - 1 ? " and " : ", ")) }
                line.append(.heard("\u{201C}\(word)\u{201D}"))
            }
            line.append(.plain(words.count == 1 ? ". It isn\u{2019}t drawn on the pitch chart." : "."))
            return line
        }
    }

    // MARK: Menus

    static let takeMenu = "Take"
    static let playModel = "Play Model"
    static let playYou = "Play You"
    static let playModelThenYou = "Play Model, Then You"
    static let stopPlaying = "Stop"
    static let showEarlierTakes = "Show Earlier Takes"

    // MARK: Live app (spec 21: v1 §10 menus, r6 E5 and E8, v1 §11.1 announcements)

    static let recordTake = "Record Take"
    static let stopRecording = "Stop Recording"
    static let cancel = "Cancel"
    static let previousTake = "Previous Take"
    static let nextTake = "Next Take"
    static let previousPhrase = "Previous Phrase"
    static let nextPhrase = "Next Phrase"
    static let details = "Details"
    static let showDetails = "Show Details"
    static let hideDetails = "Hide Details"
    static let find = "Find"
    static let input = "INPUT"
    static let tooLoud = "Too loud"

    // MARK: Input popover (v3.5 I1–I6)

    /// The toolbar button's tooltip and VoiceOver label.
    static let inputButton = "Input"
    /// The inspector, card 1 and tier A buttons that open the popover.
    static let inputEllipsis = "Input\u{2026}"
    static let microphone = "Microphone"
    static let systemDefault = "System Default"
    static let inputVolume = "Input volume"
    static let inputVolumeTooltip = "Mac input volume. This also applies in other apps."
    static let fixedLevel = "This microphone sets its own level"
    static let soundSettings = "Sound Settings\u{2026}"
    static let inputHint = "Speak at your normal volume. Aim for the middle."
    static let microphoneDisabledTooltip = "Stop recording to change the microphone"
    static let voiceDisabledTooltip = "Stop recording to change the voice"
    static let recordingAnnouncement = "Recording"
    static let analysingAnnouncement = "Analysing"
    static let recordingCancelled = "Recording cancelled"

    // MARK: Strip and pitch legends (v3 §3.2–3.3, v3.1 V2, V4)

    static let dictionaryStress = "Dictionary stress"
    static let legendYou = "You"
    static let legendNativeRange = "Native range"
    static let legendEarlierTakes = "Earlier takes"
    /// The pitch chart's end label names the native line (v3.1 V4).
    static let endLabelNative = "NATIVE"
    static let endLabelYou = "YOU"

    static func looping(_ word: String) -> String {
        "Looping \u{201C}\(word)\u{201D} \u{00B7} Esc to stop"
    }

    /// The strip card header while audio plays (Addendum r6 E4), after a ▶ glyph.
    static let playingModel = "Playing the model"
    static let playingYou = "Playing your take"

    /// Edit Transcript (r6 E2, v3 §5).
    static func editTranscriptNote(takes: Int) -> String {
        "Your \(takes) takes will be lined up with the new wording again. Takes that don\u{2019}t fit stay in the menu as not comparable."
    }

    // MARK: Inspector (v3 §4)

    static let modelRecording = "MODEL RECORDING"
    static let voice = "Voice"

    // MARK: Take problems (§11.1)

    static func takeProblem(_ problem: TakeProblem) -> String {
        switch problem {
        case .noMicrophone: "No microphone found. Connect one to record a take."
        case .micDenied: "Accent Mirror needs the microphone to hear your take."
        case .noSpeech: "No speech heard. Move a little closer to the mic and try again."
        case .tooShort: "That take was too short to line up with the model. Say the whole phrase."
        case .tooQuiet: "That take was too quiet to hear clearly. Move closer to the mic or speak up."
        case .clipped: "That take was too loud and distorted. Move back a little or lower the input level."
        case .wordsDontMatch: "Some words didn't match the phrase. Read it exactly as written, then try again."
        }
    }

    /// The caption under your strip row for a take problem with audio (§7.1, Designer answer 3 of round 3).
    static func takeProblemCaption(_ problem: TakeProblem) -> String? {
        switch problem {
        case .tooQuiet: tooQuietToMeasure
        case .clipped: tooLoudToMeasure
        case .tooShort: tooShortToMeasure
        case .wordsDontMatch: wordsDidntMatch
        case .noMicrophone, .micDenied, .noSpeech: nil
        }
    }

    static func takeProblemButton(_ problem: TakeProblem) -> String? {
        switch problem {
        case .noMicrophone: nil
        case .micDenied: "Open System Settings\u{2026}"
        default: "Try Again"
        }
    }

    // MARK: Operational banners (§13.2)

    static func banner(_ error: OperationalError) -> (sentence: String, button: String) {
        switch error.kind {
        case .modelUnavailable:
            ("Accent Mirror couldn't load its speech model, so this take can't be shown. This isn't about your take.", "Retry")
        case .inferenceFailed:
            (inferenceFailed(error.stage ?? .comparing), "Retry")
        case .referenceCacheCorrupt:
            ("Accent Mirror couldn't read its copy of this native recording.", "Rebuild")
        case .audioUnreadable:
            error.source == "take"
                ? ("Accent Mirror couldn't read the recording it just made.", "Retry")
                : ("Accent Mirror couldn't read that audio file. Try a WAV, M4A or MP3 file.", "Choose File\u{2026}")
        }
    }

    /// §13.2's frame, reworded because v3 §5 bans "wrong" in every v1 string (spec gap): "Accent Mirror ran into a
    /// problem while {stage}. This isn't about your take." No ellipsis.
    static func inferenceFailed(_ stage: OperationalError.Stage) -> String {
        "Accent Mirror ran into a problem while \(inferenceStage(stage)). This isn't about your take."
    }

    static func inferenceStage(_ stage: OperationalError.Stage) -> String {
        switch stage {
        case .findingWords: "finding your words"
        case .measuringPitch: "measuring your pitch"
        case .measuringStress: "measuring your syllables"
        case .comparing: "lining your take up with the model"
        }
    }

    static let saveFailed = "This take couldn't be saved. You can still see the result, but it won't be in your takes."
    static let saveFailedButton = "Try Again Saving"

    // MARK: Words (§8.1, §8.2, §13.4)

    static func substitutedTooltip(heard: String) -> String {
        "Heard \u{201C}\(heard)\u{201D} here."
    }

    static let missingTooltip = "Not in your take."

    // MARK: Toolbar in narrow windows (r4 C7)

    /// Tooltip and VoiceOver for Record when it is only its dot (or Stop's square).
    static func recordButtonShortLabel(stop: Bool) -> String {
        stop ? "Stop (Space)" : "Record (Space)"
    }

    /// Tooltip and VoiceOver for the take menu when it is only its chevron: "Takes", "Take 03".
    static func takeMenuShortLabel(_ label: ToolbarState.TakeMenuLabel) -> String {
        switch label {
        case .takes: "Takes"
        case .take(let number): "Take " + (number < 10 ? "0\(number)" : "\(number)")
        case .lastTryNotSaved: "Last try, not saved"
        }
    }

    /// Tooltip and VoiceOver for the take menu's count form (v3.6 J2): "Take 3", no leading zero.
    static func takeMenuCountLabel(_ label: ToolbarState.TakeMenuLabel) -> String {
        switch label {
        case .takes: "Takes"
        case .take(let number): "Take \(number)"
        case .lastTryNotSaved: "Last try, not saved"
        }
    }

    /// VoiceOver for a whole line of labels (a strip row's syllables or the pitch plot's words). It reads every
    /// label, including those hidden because the window is too narrow to show them all (fixes round 5).
    static func labelLine(_ labels: [String]) -> String {
        labels.joined(separator: ", ")
    }

    /// Tooltip over a label hidden because it didn't fit: the label itself, then its own note if it has one.
    static func hiddenLabelTooltip(_ label: String, note: String?) -> String {
        guard let note, !note.isEmpty else { return label }
        return "\(label). \(note)"
    }
    static let ambiguousTooltip = "This word can be said more than one way."
    /// VoiceOver for a native label with the dot (the dot itself isn't read on its own).
    static func dictionaryStressLabel(_ syllable: String) -> String { "\(syllable), dictionary stress" }

    // MARK: Inspector take status

    static func persistence(_ status: PersistenceStatus) -> String? {
        switch status {
        case .notSaved: "Not saved"
        case .saveFailed: "Not saved: the save failed"
        case .saved, .savedPruneFailed: nil
        }
    }
}
