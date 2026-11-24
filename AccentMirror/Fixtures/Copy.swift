import Foundation

/// A run of sentence text with its styling role. Views map roles to tokens; tests read `plain`.
struct Segment: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case plain
        /// Accepted stressed syllable or word: bold caps in lime.text.
        case stressed
        /// The wrong syllable: bold caps in mistake blue (the caps and word order also say it).
        case mistake
        /// A heard word (insertions, substitutions): italics.
        case heard
    }

    var text: String
    var role: Role

    static func plain(_ text: String) -> Segment { Segment(text: text, role: .plain) }
    static func stressed(_ text: String) -> Segment { Segment(text: text, role: .stressed) }
    static func mistake(_ text: String) -> Segment { Segment(text: text, role: .mistake) }
    static func heard(_ text: String) -> Segment { Segment(text: text, role: .heard) }
}

typealias Sentence = [Segment]

extension Array where Element == Segment {
    var plain: String { map(\.text).joined() }
}

/// Every user-facing sentence of the fixture-driven shell, from Designer spec v2 §10, §11.1, §13 and Addendum r2.
/// Pure functions of contract values, so the copy is testable without UI. Spec 28: nothing here reads a verdict, a
/// diff row, a stress line or a measure state; that copy waits, unused by the views, in `VerdictSentences.swift` for spec
/// 29 to delete with its banned-word test.
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
    static let unalignable = "This take was recorded for the old wording, so it can't be compared."
    static let notComparable = "NOT COMPARABLE"
    static let notComparableTooltip = "Recorded for the old wording, so it can't be lined up with the new one."

    // MARK: Quiet lines (A6)

    /// All quiet lines in priority order: insertions, then incomplete non-target words, then the count.
    static func quietLines(_ notes: QuietNotes?) -> [Sentence] {
        guard let notes else { return [] }
        var lines: [Sentence] = []
        if let insertions = notes.insertions, !insertions.isEmpty {
            var line: Sentence = [.plain("You added ")]
            for (index, word) in insertions.enumerated() {
                if index > 0 { line.append(.plain(index == insertions.count - 1 ? " and " : ", ")) }
                line.append(.heard("\u{201C}\(word)\u{201D}"))
            }
            line.append(.plain(insertions.count == 1 ? ". It's left out of the comparison." : "."))
            lines.append(line)
        }
        if notes.nonTargetWordsIncomplete == true {
            lines.append([.plain("Some words weren't clear enough to compare. Feedback covers the rest.")])
        }
        if let partial = notes.partial {
            lines.append([.plain("Feedback covers \(partial.compared) of \(partial.total) words.")])
        }
        return lines
    }

    // MARK: Take problems (§11.1)

    static func takeProblem(_ problem: TakeProblem) -> String {
        switch problem {
        case .noMicrophone: "No microphone found. Connect one to record a take."
        case .micDenied: "Accent Mirror needs the microphone to hear your take."
        case .noSpeech: "No speech heard. Move a little closer to the mic and try again."
        case .tooShort: "That take was too short to compare. Say the whole phrase."
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
            ("Accent Mirror couldn't load its speech model, so this take wasn't checked. This isn't about your take.", "Retry")
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

    /// §13.2: "Something went wrong inside Accent Mirror while {stage}. This isn't about your take." No ellipsis.
    static func inferenceFailed(_ stage: OperationalError.Stage) -> String {
        "Something went wrong inside Accent Mirror while \(inferenceStage(stage)). This isn't about your take."
    }

    static func inferenceStage(_ stage: OperationalError.Stage) -> String {
        switch stage {
        case .findingWords: "finding your words"
        case .measuringPitch: "measuring your pitch"
        case .measuringStress: "measuring stress"
        case .comparing: "comparing with the model"
        }
    }

    static let saveFailed = "This take couldn't be saved. You can still see the result, but it won't be in your takes."
    static let saveFailedButton = "Try Again Saving"

    // MARK: Words (§8.1, §8.2, §13.4)

    static func substitutedTooltip(heard: String, expected: String) -> String {
        "You said \u{201C}\(heard)\u{201D} here, not \u{201C}\(expected)\u{201D}."
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

    /// VoiceOver for the mistake marker on a strip label (the triangle and underline are not read).
    static func mistakeLabelAccessibility(_ syllable: String) -> String {
        "\(syllable), stressed differently from the model"
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
    static let ambiguousTooltip = "Stress isn't checked on this word. It can be said more than one way."

    // MARK: Inspector (§14)

    static func persistence(_ status: PersistenceStatus) -> String? {
        switch status {
        case .notSaved: "Not saved"
        case .saveFailed: "Not saved: the save failed"
        case .saved, .savedPruneFailed: nil
        }
    }
}
