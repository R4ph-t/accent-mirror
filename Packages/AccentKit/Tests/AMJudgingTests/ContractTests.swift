import AMCore
import AMJudging
import Foundation
import Testing

@Suite struct SoundJudgementContractTests {
    func phone(_ p: String, _ confidence: Double, flagged: Bool) -> JudgedPhone {
        JudgedPhone(phone: p, gop: flagged ? -9 : -0.1, confidence: confidence, flagged: flagged,
                    heardInstead: flagged ? .sound("s") : nil, youRange: try? TimeRange(start: 0.1, end: 0.2))
    }

    @Test func outcomeRoundTripsThroughJSON() throws {
        let words = [
            JudgedWord(index: WordIndex(0), text: "think", youRange: try TimeRange(start: 0, end: 0.4),
                       modelRange: try TimeRange(start: 0.1, end: 0.5),
                       state: .judged([phone("TH", 0.2, flagged: true), phone("IH", 0.97, flagged: false)])),
            JudgedWord(index: WordIndex(1), text: "zyzzyva", youRange: nil, modelRange: nil,
                       state: .unjudged(.notInDictionary)),
        ]
        let outcome = SoundJudgementOutcome.judged(
            SoundJudgement(modelID: "m", judgeID: SoundScorer.judgeID, errorThreshold: 0.22, words: words))
        let data = try JSONEncoder().encode(outcome)
        #expect(try JSONDecoder().decode(SoundJudgementOutcome.self, from: data) == outcome)
        let unavailable = SoundJudgementOutcome.unavailable(.modelNotInstalled)
        #expect(try JSONDecoder().decode(SoundJudgementOutcome.self, from: JSONEncoder().encode(unavailable))
            == unavailable)
    }

    @Test func wordIsFlaggedWhenAnySoundIsAndFlaggedSoundsSortLeastConfidentFirst() throws {
        let a = JudgedWord(index: WordIndex(0), text: "a", youRange: nil, modelRange: nil,
                           state: .judged([phone("AH", 0.4, flagged: true)]))
        let b = JudgedWord(index: WordIndex(1), text: "b", youRange: nil, modelRange: nil,
                           state: .judged([phone("B", 0.9, flagged: false), phone("IY", 0.1, flagged: true)]))
        let c = JudgedWord(index: WordIndex(2), text: "c", youRange: nil, modelRange: nil,
                           state: .unjudged(.notInDictionary))
        #expect(a.flagged && b.flagged && !c.flagged)
        let j = SoundJudgement(modelID: "m", judgeID: "j", errorThreshold: 0.22, words: [a, b, c])
        #expect(j.flaggedSounds.map(\.phone.phone) == ["IY", "AH"])
    }
}
