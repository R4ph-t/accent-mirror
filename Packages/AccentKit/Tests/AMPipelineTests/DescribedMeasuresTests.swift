// Spec 28 §4a: one function, the same frames. For two starter phrases, your values and each native's, run through
// `ProsodyDescription.speaker`, equal what AMScoring computes for the same frames, and the native range covers every
// bundled voice.

import AMAlignment
import AMCore
import AMLibrary
@testable import AMPipeline
import AMPlacement
import AMProsody
import AMScoring
import AMVerdicts
import AMWarp
import Foundation
import Testing

@Suite("Descriptive measures (spec 28 §4a)", .serialized) struct DescribedMeasuresTests {
    @Test("you and every native equal AMScoring's values on the same frames; the range covers every voice")
    func sameFunctionSameFrames() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let cases = Array(try world.cases().filter { $0.phrase.recordings.count >= 3 }.prefix(2))
        #expect(cases.count == 2)
        let thresholds = Thresholds.current
        for c in cases {
            let voice = c.phrase.headlineVoice
            let run = await world.analyzer(c).run(take: c.take, phrase: c.input, reference: world.library, voice: voice)
            guard case .analysed(let result) = run.response.outcome, let describe = result.describe else {
                Issue.record("\(c.phrase.id): \(run.response.outcome)")
                continue
            }
            let natives = try await world.natives(c.phrase.id)
            let model = try #require(natives.first { $0.recording.id == voice }).analysis.l1.analysis
            let l1 = try #require(run.derived.first { $0.level == .l1 })
            let yours = try JSONDecoder().decode(L1Analysis.self, from: l1.bytes).analysis

            var speakers: [(name: String, prosody: TakeProsody)] = [("you", yours)]
            speakers += natives.map { ($0.recording.voice, $0.analysis.l1.analysis) }
            var compared = 0
            var nativeDescriptions: [SpeakerDescription] = []
            for (name, prosody) in speakers {
                guard let warp = try? PairScoring.warp(you: prosody, model: model, words: c.input.words, thresholds: thresholds)
                else { continue }
                let described = ProsodyDescription.speaker(prosody, warp: warp, thresholds: thresholds)
                if name == "you" {
                    #expect(described == describe.you, "\(c.phrase.id): the result's description is the function's")
                } else {
                    nativeDescriptions.append(described)
                }
                // AMScoring on the same pair: this speaker as "you", warped onto the selected model.
                let scoring = try Scorer.score(
                    PairScoring.input(
                        words: c.input.words, you: prosody, model: model, modelVoice: "model", natives: [:], warp: warp,
                        thresholds: thresholds),
                    thresholds: thresholds)
                let pairs: [(MeasureKind, DescribedValue)] = [
                    (.pitchRange, described.pitchRangeSemitones), (.rhythm, described.rhythmNPVI),
                    (.finalDirection, described.finalSlope),
                ]
                for (kind, value) in pairs {
                    guard let scored = scoring.measures.states[kind]?.value else { continue }
                    #expect(value.value == scored, "\(c.phrase.id) \(name) \(kind)")
                    compared += 1
                }
                if let slope = described.finalSlope.value {
                    #expect(described.endingDirection == PitchDirection(slope: slope, thresholds: thresholds.finalDirection))
                }
            }
            #expect(compared >= speakers.count, "\(c.phrase.id): enough measures compared (\(compared))")

            // The native range: every bundled voice, each inside min–max.
            #expect(describe.native.voices == natives.count, "\(c.phrase.id)")
            #expect(describe.native.voices == nativeDescriptions.count, "every native warped onto the model")
            func covers(_ range: DescribedRange, _ value: DescribedValue) -> Bool {
                guard let v = value.value else { return true }
                guard let lo = range.min, let hi = range.max else { return false }
                return lo <= v && v <= hi
            }
            for d in nativeDescriptions {
                #expect(covers(describe.native.lengthSeconds, d.lengthSeconds))
                #expect(covers(describe.native.syllablesPerSecond, d.syllablesPerSecond))
                #expect(covers(describe.native.pitchRangeSemitones, d.pitchRangeSemitones))
                #expect(covers(describe.native.rhythmNPVI, d.rhythmNPVI))
                #expect(covers(describe.native.finalSlope, d.finalSlope))
            }
            #expect(describe.native.endingDirections.values.reduce(0, +) == describe.native.finalSlopes.count)
        }
    }
}
