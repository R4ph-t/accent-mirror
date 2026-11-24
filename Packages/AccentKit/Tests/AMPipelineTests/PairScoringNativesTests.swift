import AMAlignment
import AMCore
import AMPipeline
import AMProsody
import Foundation
import Testing

/// `PairScoring.score(natives:)` (spec 22's end-to-end check passes the synthetic reference's observed primaries):
/// a native reader's high-confidence primary joins A(w), and no native readers leaves spec 10's scoring unchanged.
@Suite("Pair scoring with native readers") struct PairScoringNativesTests {
    @Test("your own high-confidence primaries as native readings leave no placement row; none changes nothing")
    func nativesJoinAcceptedSet() async throws {
        let detectorDir = SmokePlacementGoldenTests.detector
        let inputs = try JSONDecoder().decode(
            PlacementFixtureFile.self, from: Data(contentsOf: detectorDir.appendingPathComponent("inputs.json")))
        let timings = try FixtureTimestamper(directory: detectorDir.appendingPathComponent("timestamps"))
        let detector = try StressPlacementDetector.bundled()
        let candidates = SmokeVerdict.candidates(inputs.items)
        let vctk = inputs.items.filter { candidates[$0.item] != nil }
        var analyses: [String: PlacementAnalysis] = [:]
        for item in vctk {
            let samples = try SmokePlacementGoldenTests.readMono(SmokePlacementGoldenTests.smoke.appendingPathComponent(item.audio))
            let heard = try #require(timings.recording(for: item.item)).words
            analyses[item.item] = try await detector.analyse(
                try item.take(samples: samples, sampleRate: 16_000, heard: heard, asrModelID: timings.asrModelID))
        }
        var scored = 0
        for item in vctk {
            let you = try #require(analyses[item.item])
            let words = try item.words.map {
                PlacementTake.Word(
                    index: WordIndex($0.index), text: $0.text, pronunciation: try Pronunciation(arpabet: $0.phones),
                    accepted: $0.accepted.map(Set.init))
            }
            for model in candidates[item.item] ?? [] {
                guard let modelAnalysis = analyses[model.item],
                    let plain = try? PairScoring.score(
                        words: words, you: you, model: modelAnalysis, modelVoice: model.speaker)
                else { continue }
                let empty = try PairScoring.score(
                    words: words, you: you, model: modelAnalysis, modelVoice: model.speaker, natives: [:])
                #expect(empty.decision == plain.decision, "\(item.item) vs \(model.item): no natives, same decision")

                var natives: [WordIndex: [NativeReading]] = [:]
                for result in you.words {
                    guard let observed = result.observed else { continue }
                    natives[result.word] = [NativeReading(voice: "synthetic", observed: ObservedStress(
                        primary: observed.primary, secondary: nil, margin: observed.margin, marginConfidence: .high,
                        syllableConfidence: .high, exposed: false))]
                }
                let withNatives = try PairScoring.score(
                    words: words, you: you, model: modelAnalysis, modelVoice: model.speaker, natives: natives)
                #expect(!withNatives.diffs.contains { $0.kind == .placement }, "\(item.item) vs \(model.item)")
                scored += 1
                break
            }
        }
        #expect(scored > 0, "at least one smoke pair scored")
    }
}
