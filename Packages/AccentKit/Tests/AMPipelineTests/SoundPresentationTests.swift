import AMCore
import Foundation
import Testing
@testable import AMPipeline

// Designer addendum v5 (sound flags and word playback) and the rulings of 2026-11-25.

private func range(_ start: Double, _ end: Double) -> TimeRange {
    try! TimeRange(start: start, end: end)
}

private func phone(_ symbol: String, confidence: Double = 0.9, flagged: Bool = false,
                   heard: HeardInstead? = nil, at r: TimeRange? = nil) -> JudgedPhone {
    JudgedPhone(phone: symbol, gop: -1, confidence: confidence, flagged: flagged, heardInstead: heard, youRange: r)
}

private func word(_ index: Int, _ text: String, you: TimeRange? = range(0, 1), _ phones: [JudgedPhone]) -> JudgedWord {
    JudgedWord(index: WordIndex(index), text: text, youRange: you, modelRange: nil, state: .judged(phones))
}

private func judgement(_ words: [JudgedWord]) -> SoundJudgement {
    SoundJudgement(modelID: "m", judgeID: "gop-sf-1", errorThreshold: 0.22, words: words)
}

struct SoundLabelTests {
    static let cmudict = "AA AE AH AO AW AY EH ER EY IH IY OW OY UH UW B CH D DH F G HH JH K L M N NG P R S SH T TH V W Y Z ZH"
        .split(separator: " ").map(String.init)

    @Test func everyCMUdictPhoneHasAPlainLabelAndIPA() {
        #expect(Self.cmudict.count == 39)
        for symbol in Self.cmudict {
            let label = SoundLabels.expected(symbol)
            #expect(label != nil, "\(symbol)")
            #expect(label?.plain.contains(" as in ") == true, "\(symbol)")
            #expect(label?.ipa.hasPrefix("/") == true && label?.ipa.hasSuffix("/") == true, "\(symbol)")
            // No ARPAbet code leaks into the visible label.
            #expect(label?.plain.contains(symbol) == false || symbol.count == 1, "\(symbol)")
        }
    }

    @Test func labelsMatchTheAddendum() {
        #expect(SoundLabels.expected("TH")?.plain == "th as in think")
        #expect(SoundLabels.expected("TH")?.ipa == "/θ/")
        #expect(SoundLabels.expected("ZH")?.plain == "s as in vision")
        #expect(SoundLabels.expected("ER")?.plain == "ir as in bird")
    }

    @Test func schwaStaysApartFromStressedAH() {
        #expect(SoundLabels.expected("AH0") == SoundLabel(plain: "a as in about", ipa: "/ə/"))
        #expect(SoundLabels.expected("AH") == SoundLabel(plain: "u as in cup", ipa: "/ʌ/"))
        #expect(SoundLabels.expected("AH1")?.plain == "u as in cup")
        #expect(SoundLabels.expected("IY0")?.plain == "ee as in see")
    }

    @Test func heardTokensMapOnlyWhenUnambiguous() {
        #expect(SoundLabels.heard("t")?.plain == "t as in tin")
        #expect(SoundLabels.heard("θ")?.plain == "th as in think")
        #expect(SoundLabels.heard("ə")?.plain == "a as in about")
        #expect(SoundLabels.heard("iː")?.plain == "ee as in see")
        for token in ["ɾ", "ʔ", "e", "ᵻ", "ɪɹ", "ɑːɹ", "əl", "x"] {
            #expect(SoundLabels.heard(token) == nil, "\(token)")
        }
    }
}

struct SoundHintTests {
    @Test func aClearOtherSoundReadsSoundedCloserTo() {
        let hint = SoundHint(word: word(0, "Throughout", []), phone: phone("TH", flagged: true, heard: .sound("t")))
        #expect(hint.expected.plain == "th as in think")
        #expect(hint.heardLine == "sounded closer to t as in tin")
        #expect(hint.ipaLine == "Expected /θ/ \u{00B7} sounded closer to /t/")
        #expect(hint.spokenIPA == "Expected /θ/, heard /t/")
    }

    @Test(arguments: [HeardInstead?.none, .nothing, .sound("ʔ"), .sound("θ"), .sound("ɑ")])
    func noClearOtherSoundReadsUnclear(_ heard: HeardInstead?) {
        // Nothing beat it, it seems missing, the token has no plain label, or it maps back to the expected sound.
        let expected = heard == .sound("ɑ") ? "AA" : "TH"
        let hint = SoundHint(word: word(0, "w", []), phone: phone(expected, flagged: true, heard: heard))
        #expect(hint.heard == .unclear)
        #expect(hint.heardLine == "sounded unclear")
        #expect(!hint.heardLine.contains("closer"))
    }

    @Test func aSoundInAWordYouDidntSayHasNoRange() {
        let hint = SoundHint(word: word(0, "w", you: nil, []), phone: phone("T", flagged: true, at: range(1, 2)))
        #expect(hint.youRange == nil)
    }

    @Test func noHintLineUsesABannedWordOrANumber() {
        let banned = ["wrong", "error", "mistake", "bad", "fail", "grade", "score"]
        for symbol in SoundLabelTests.cmudict + ["AH0"] {
            for heard in [HeardInstead.sound("t"), .nothing] {
                let hint = SoundHint(word: word(0, "w", []), phone: phone(symbol, confidence: 0.12, flagged: true, heard: heard))
                for text in [hint.expected.plain, hint.heardLine] {
                    #expect(!banned.contains { text.lowercased().contains($0) }, "\(text)")
                    #expect(!text.contains { $0.isNumber }, "\(text)")
                }
            }
        }
    }
}

struct SoundsToCheckTests {
    /// Five flagged words with their least confident flagged sound: 0.30, 0.10, 0.20, 0.40, 0.05.
    static let five = judgement([
        word(0, "Throughout", [phone("TH", confidence: 0.3, flagged: true, heard: .sound("t")), phone("R")]),
        word(1, "the", [phone("DH"), phone("AH0")]),
        word(2, "centuries", [phone("S", confidence: 0.1, flagged: true, heard: .sound("z")),
                              phone("EH", confidence: 0.15, flagged: true)]),
        word(3, "explained", [phone("D", confidence: 0.2, flagged: true, heard: .sound("t"))]),
        word(4, "rainbow", [phone("R", confidence: 0.4, flagged: true, heard: .sound("l"))]),
        word(5, "various", [phone("V", confidence: 0.05, flagged: true, heard: .sound("w"))]),
    ])

    @Test func showsTheThreeLeastConfidentWordsAndCountsTheRest() {
        let card = SoundsToCheck.rows(Self.five)
        #expect(card.rows.map(\.word) == ["various", "centuries", "explained"])
        #expect(card.more == 2)
    }

    @Test func eachRowShowsItsWordsLeastConfidentFlaggedSound() {
        let centuries = SoundsToCheck.rows(Self.five).rows[1]
        #expect(centuries.expected.plain == "s as in sit")
        #expect(centuries.heardLine == "sounded closer to z as in zoo")
    }

    @Test func thePopoverListsEveryFlaggedSoundInWordOrder() {
        let hints = SoundsToCheck.hints(Self.five.words[2])
        #expect(hints.map(\.expected.plain) == ["s as in sit", "e as in bed"])
        #expect(SoundsToCheck.hints(Self.five.words[1]).isEmpty)
    }

    @Test func threeOrFewerFlagsShowNoMoreLine() {
        let three = judgement(Array(Self.five.words.prefix(4)))
        #expect(SoundsToCheck.rows(three).rows.count == 3)
        #expect(SoundsToCheck.rows(three).more == 0)
        #expect(SoundsToCheck.rows(judgement([word(0, "a", [phone("AH0")])])).rows.isEmpty)
    }

    @Test func tiesKeepPhraseOrder() {
        let tied = judgement([
            word(0, "one", [phone("W", confidence: 0.2, flagged: true)]),
            word(1, "two", [phone("T", confidence: 0.2, flagged: true)]),
        ])
        #expect(SoundsToCheck.rows(tied).rows.map(\.word) == ["one", "two"])
    }

    @Test func aWordYouDidntSayIsNeverFlagged() {
        let missing = word(0, "gone", you: nil, [phone("G", confidence: 0.01, flagged: true)])
        #expect(!SoundsToCheck.isFlagged(missing))
        #expect(SoundsToCheck.rows(judgement([missing])).rows.isEmpty)
        #expect(SoundsToCheck.hints(missing).isEmpty)
    }

    @Test func unjudgedWordsAreNeverFlagged() {
        let oov = JudgedWord(index: WordIndex(0), text: "Grok", youRange: range(0, 1), modelRange: nil,
                             state: .unjudged(.notInDictionary))
        #expect(!SoundsToCheck.isFlagged(oov))
    }
}

struct SegmentWindowTests {
    @Test func padsThirtyMillisecondsEachSide() {
        let window = SegmentWindow.padded(range(1.0, 1.2), previousEnd: nil, nextStart: nil)
        #expect(abs(window.start - 0.97) < 1e-9)
        #expect(abs(window.end - 1.23) < 1e-9)
        #expect(SegmentWindow.fade == 0.01)
    }

    @Test func neverReachesIntoTheNeighbouringWords() {
        let window = SegmentWindow.padded(range(1.0, 1.2), previousEnd: 0.99, nextStart: 1.21)
        #expect(window.start == 0.99)
        #expect(window.end == 1.21)
    }

    @Test func aRangeThatAlreadyOverlapsAWordKeepsItsOwnEdges() {
        let window = SegmentWindow.padded(range(1.0, 1.2), previousEnd: 1.05, nextStart: 1.1)
        #expect(window.start == 1.0)
        #expect(window.end == 1.2)
    }

    @Test func neverStartsBeforeTheTake() {
        #expect(SegmentWindow.padded(range(0.01, 0.2), previousEnd: nil, nextStart: nil).start == 0)
    }

    @Test func wordsAndSoundsClampToTheHeardWordsEitherSide() throws {
        let words = judgement([
            word(0, "one", you: range(0.5, 0.8), []),
            word(1, "gone", you: nil, []),
            word(2, "two", you: range(0.82, 1.1), [phone("T", flagged: true, at: range(0.82, 0.9))]),
            word(3, "three", you: range(1.12, 1.5), []),
        ])
        let two = try #require(SegmentWindow.you(word: 2, in: words))
        #expect(two.start == 0.8)
        #expect(two.end == 1.12)
        #expect(SegmentWindow.you(word: 1, in: words) == nil)
        let sound = SegmentWindow.you(sound: range(0.82, 0.9), word: 2, in: words)
        #expect(sound.start == 0.8)
        #expect(abs(sound.end - 0.93) < 1e-9)
    }
}
