import AMAlignment
import AMCore
import AMPipeline
import AMPlacement
import AMProsody
import AMVerdicts
import AVFoundation
import Foundation
import Testing

/// Spec 02's smoke set, spec 08's goldens: per item the L1 digest and each decided word's placement before and after
/// suppression, from committed inputs and replayed word timings (no ASR, no corpus, no tagger). Never a rate gate.
/// Re-record with `scripts/am-eval.sh smoke-detector --record` after a version bump.
@Suite("SmokePlacementGoldenTests") struct SmokePlacementGoldenTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AMPipelineTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // AccentKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
    static let smoke = root.appendingPathComponent("fixtures/smoke")
    static let detector = smoke.appendingPathComponent("detector")

    static func readMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        #expect(file.processingFormat.sampleRate == 16_000)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    @Test("every smoke item reproduces its L1 digest and placements before and after suppression")
    func goldens() async throws {
        let inputs = try JSONDecoder().decode(
            PlacementFixtureFile.self, from: Data(contentsOf: Self.detector.appendingPathComponent("inputs.json")))
        let goldens = try JSONDecoder().decode(
            PlacementGoldenFile.self, from: Data(contentsOf: Self.detector.appendingPathComponent("goldens.json")))
        let timings = try FixtureTimestamper(directory: Self.detector.appendingPathComponent("timestamps"))
        #expect(goldens.asrModelID == timings.asrModelID)
        #expect(goldens.algorithmVersion == Versions.algorithmVersion, "re-record the goldens after a version bump")
        #expect(goldens.thresholdsVersion == Versions.thresholdsVersion, "re-record the goldens after a version bump")
        #expect(inputs.items.count == goldens.items.count)
        #expect(inputs.items.count == 53)

        let detector = try StressPlacementDetector.bundled()
        var analyses: [String: PlacementAnalysis] = [:]
        for item in inputs.items {
            let samples = try Self.readMono(Self.smoke.appendingPathComponent(item.audio))
            let heard = try #require(timings.recording(for: item.item)).words
            let take = try item.take(samples: samples, sampleRate: 16_000, heard: heard, asrModelID: timings.asrModelID)
            analyses[item.item] = try await detector.analyse(take)
        }
        let candidates = SmokeVerdict.candidates(inputs.items)
        #expect(candidates.count == 6, "every VCTK item has model candidates; speechocean762 items have none")
        for (item, golden) in zip(inputs.items, goldens.items) {
            #expect(item.item == golden.item)
            let analysis = try #require(analyses[item.item])
            let result = try PlacementGolden(item: item, analysis: analysis)
            #expect(result.l1Digest == golden.l1Digest, "\(item.item): L1 digest")
            #expect(result.words == golden.words, "\(item.item): placements")
            // Spec 10: the verdict per item against its model (VCTK items only).
            let verdict = try candidates[item.item].map { models in
                try SmokeVerdict.score(
                    item: item, analysis: analysis, candidates: models.map { ($0, analyses[$0.item]!) })
            }
            #expect(verdict == golden.verdict, "\(item.item): verdict")
            #expect((golden.verdict == nil) == (item.corpus != "vctk"), "\(item.item): verdict presence")
        }
    }

    @Test("the replayed timings belong to the committed audio") func timingsMatchAudio() throws {
        let inputs = try JSONDecoder().decode(
            PlacementFixtureFile.self, from: Data(contentsOf: Self.detector.appendingPathComponent("inputs.json")))
        let timings = try FixtureTimestamper(directory: Self.detector.appendingPathComponent("timestamps"))
        for item in inputs.items {
            #expect(timings.recording(for: item.item)?.audioSHA256 == item.audioSHA256, "\(item.item)")
        }
    }
}
