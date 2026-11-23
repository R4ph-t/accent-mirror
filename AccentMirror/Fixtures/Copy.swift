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
/// Pure functions of contract values, so the copy is testable without UI.
enum Copy {
    // MARK: Card 1 titles

    static let whatToChange = "WHAT TO CHANGE"
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

    // MARK: Diff rows (§10)

    static func row(_ row: DiffRow) -> Sentence {
        switch row.kind {
        case .roughTiming:
            return [.plain("The timing match for this take is rough, so syllable lengths may be off.")]
        case .placement:
            return placement(row)
        case .contrast:
            let targets = row.targets ?? []
            return [.plain("Make ")] + joinedStressed(targets) +
                [.plain(" stronger. Right now they sound like the syllables around them.")]
        case .reduction:
            return [.plain("Keep the small syllables short and light: " + (row.targets ?? []).joined(separator: ", ") + ".")]
        case .range:
            return [.plain("Use more of your voice range. Your pitch stays flatter than the model's.")]
        case .finalDirection:
            return [.plain(row.direction == "higher" ? "End higher, the way the model does." : "End lower, the way the model does.")]
        case .tooMuchContrast:
            // Names every syllable that's over (Designer, round 4): "You can soften HAR and LOOKS a little."
            let targets = row.targets ?? []
            return [.plain("You can soften ")] + joinedStressed(targets) +
                [.plain(" a little. The model doesn't push \(targets.count > 1 ? "them" : "it") as hard.")]
        }
    }

    /// "Stress TOG, not PHO: phoTOGraphy." or "…, like p311 says it." (§13.5). Never "wrong".
    private static func placement(_ row: DiffRow) -> Sentence {
        let syllables = row.syllables ?? []
        let accepted = row.acceptedIndex ?? 0
        let heard = row.heardIndex ?? 0
        guard syllables.indices.contains(accepted), syllables.indices.contains(heard) else { return [] }
        var sentence: Sentence = [
            .plain("Stress "), .stressed(syllables[accepted].uppercased()),
            .plain(", not "), .mistake(syllables[heard].uppercased()), .plain(": "),
        ]
        let before = syllables[..<accepted].joined()
        let after = syllables[(accepted + 1)...].joined()
        if !before.isEmpty { sentence.append(.plain(before)) }
        sentence.append(.stressed(syllables[accepted].uppercased()))
        if !after.isEmpty { sentence.append(.plain(after)) }
        sentence.append(.plain(row.likeVoice.map { ", like \($0) says it." } ?? "."))
        return sentence
    }

    /// "A", "A and B", "A, B and C", each in bold caps.
    private static func joinedStressed(_ words: [String]) -> Sentence {
        var out: Sentence = []
        for (index, word) in words.enumerated() {
            if index > 0 { out.append(.plain(index == words.count - 1 ? " and " : ", ")) }
            out.append(.stressed(word.uppercased()))
        }
        return out
    }

    // MARK: Close (A4)

    static func close(measures: [MeasureState]) -> Sentence {
        if placementOnlyReason(measures) == "oneWordTwoSyllables" {
            return [.plain("Close to the model. Stress is in the right place.")]
        }
        let pitchShape = measures.first { $0.measure == .pitchShape }
        if pitchShape?.state == .evaluated {
            return [.plain("Close to the model. Stress, rhythm and pitch shape all match.")]
        }
        return [.plain("Close to the model. Stress and rhythm match.")]
    }

    // MARK: Placement-only line (§13.3)

    static func placementOnlyReason(_ measures: [MeasureState]) -> String? {
        guard let contrast = measures.first(where: { $0.measure == .contrast }), contrast.state == .notApplicable
        else { return nil }
        return contrast.reason
    }

    static func placementOnlyLine(_ measures: [MeasureState]) -> Sentence? {
        switch placementOnlyReason(measures) {
        case "oneWordTwoSyllables":
            [.plain("This phrase gets stress placement feedback only: one word with two syllables has nothing else to compare.")]
        case "tooFewExpectedUnstressed":
            [.plain("This phrase gets stress placement feedback only. It's too short to compare strong and weak syllables.")]
        default:
            nil
        }
    }

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

    // MARK: noClearDifference (§13.1)

    /// The card 1 sentence for the first reason that has one. When every reason is covered only by an A6 quiet
    /// line (insertionsPresent, nonTargetWordsIncomplete), the row still shows, with the stem the §13.1
    /// sentences share; the quiet line then sits under it.
    static func noClearDifference(_ reasons: [NoClearDifferenceReason]) -> Sentence {
        let ordered = NoClearDifferenceReason.allCases.filter(reasons.contains)
        for reason in ordered {
            if let sentence = noClearDifferenceSentence(reason) { return [.plain(sentence)] }
        }
        return [.plain(noClearDifferenceStem)]
    }

    static let noClearDifferenceStem = "No clear difference in stress or rhythm."

    static func noClearDifferenceSentence(_ reason: NoClearDifferenceReason) -> String? {
        switch reason {
        case .pitchShapeBelowClose:
            "No clear difference in stress or rhythm. Your pitch moves a little differently from the model's, but not in one place we can point to."
        case .optionalMeasuresUnavailable:
            "No clear difference in stress or rhythm. Some pitch measures couldn't be taken on this take."
        case .mediumConfidenceOnly:
            "Nothing stood out clearly enough to point at. Try another take to check."
        case .timingRough:
            "No clear difference, but the timing match was rough, so small differences may be hidden."
        case .nonTargetWordsIncomplete, .insertionsPresent:
            nil
        }
    }

    static func noClearDifferenceReasonName(_ reason: NoClearDifferenceReason) -> String {
        switch reason {
        case .pitchShapeBelowClose: "Pitch shape below close"
        case .optionalMeasuresUnavailable: "Optional measures unavailable"
        case .mediumConfidenceOnly: "Medium confidence only"
        case .timingRough: "Timing rough"
        case .nonTargetWordsIncomplete: "Non-target words incomplete"
        case .insertionsPresent: "Insertions present"
        }
    }

    // MARK: inconclusive (§13.1)

    static func inconclusive(_ value: Inconclusive) -> Sentence {
        switch value.reason {
        case .targetWordsMissing:
            let words = value.words ?? []
            let subject: String
            switch words.count {
            case 1: subject = "\u{201C}\(words[0])\u{201D}, so we can't check its stress"
            case 2: subject = "\u{201C}\(words[0])\u{201D} and \u{201C}\(words[1])\u{201D}, so we can't check their stress"
            default: subject = "some of the key words, so we can't check their stress"
            }
            return [.plain("We didn't hear \(subject). Say the whole phrase and try again.")]
        case .timingUnreliable:
            return [.plain("We couldn't line your take up with the model well enough to compare. Try again at an even pace.")]
        case .comparableCoverageLow:
            let percent = Int(((value.coverage ?? 0) * 100 / 5).rounded()) * 5
            return [.plain("Only part of your take lined up with the model (about \(percent)%). Say the whole phrase in one go.")]
        case .requiredMeasureUnavailable:
            if value.cause == "lowConfidence" {
                return [.plain("We couldn't tell your stress clearly on this take. Try again a little slower.")]
            }
            return [.plain("We couldn't measure stress on this take. Try again a little louder and closer to the mic.")]
        case .noApplicableStressMeasure:
            return [.plain("This phrase has no word long enough to check stress on. The charts still show your rhythm and pitch.")]
        }
    }

    static func inconclusiveHasTryAgain(_ value: Inconclusive) -> Bool {
        value.reason != .noApplicableStressMeasure
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

    // MARK: Inspector (§13.5, §13.9, §14)

    /// Nil for a word stressed outside the accepted set: §13.5 gives that word a placement row, not an
    /// inspector line (see the PR's spec gaps).
    static func stressLine(_ line: StressLine) -> String? {
        let pattern = line.pattern.map { " (\($0))" } ?? ""
        switch line.outcome {
        case .matchesVoice:
            return "\(line.word): you match \(line.voice ?? "the model")\(pattern)."
        case .matchesDictionary:
            return "\(line.word): you match the dictionary\(pattern)."
        case .differsButAccepted:
            return "\(line.word): different from \(line.selectedVoice ?? "the model"), but you match \(line.voice ?? "another voice"). Both are natural."
        case .outsideAccepted:
            return nil
        case .lowConfidence:
            return "\(line.word): not clear enough to check."
        case .referenceAnomaly:
            return "\(line.voice ?? "The model") stresses this word differently from the dictionary, so it isn't compared."
        case .notChecked:
            return "\(line.word): \(ambiguousTooltip)"
        }
    }

    static func measureName(_ measure: MeasureState.Measure) -> String {
        switch measure {
        case .stressPlacement: "Stress placement"
        case .contrast: "Contrast"
        case .reduction: "Reduction"
        case .rhythm: "Rhythm"
        case .pitchShape: "Pitch shape"
        case .range: "Range"
        case .finalDirection: "Final direction"
        }
    }

    /// "Evaluated · 0.82", "Not measured: too little voicing", "Not applicable: one word with two syllables".
    static func measureValue(_ state: MeasureState) -> String {
        switch state.state {
        case .evaluated:
            return state.value.map { String(format: "%.2f", $0) } ?? "Evaluated"
        case .unavailable:
            return "\u{2014}  Not measured: " + (state.reason.map(reasonText) ?? "unavailable")
        case .notApplicable:
            return "Not applicable: " + (state.reason.map(reasonText) ?? "not applicable")
        }
    }

    static func reasonText(_ reason: String) -> String {
        switch reason {
        case "tooLittleVoicing": "too little voicing"
        case "oneWordTwoSyllables": "one word with two syllables"
        case "tooFewExpectedUnstressed": "too few weak syllables"
        case "lowConfidence": "low confidence"
        case "noFinalVoicing": "no voicing at the end"
        default: reason
        }
    }

    static func persistence(_ status: PersistenceStatus) -> String? {
        switch status {
        case .notSaved: "Not saved"
        case .saveFailed: "Not saved: the save failed"
        case .saved, .savedPruneFailed: nil
        }
    }
}
