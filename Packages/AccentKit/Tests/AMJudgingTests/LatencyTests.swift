@testable import AMJudging
import AMCore
import AVFoundation
import Foundation
import Testing

/// Hand check on a Mac with the model: `AM_JUDGE_MODEL_DIR=<folder with manifest.json and LV60Int8.mlmodelc>`.
/// Skipped (with a message) everywhere else, CI included: the model is never in the repo. The bar is for optimised
/// builds: `AM_JUDGE_MODEL_DIR=… swift test -c release -Xswiftc -enable-testing --filter LatencyTests`.
@Suite("Sound judge latency (needs AM_JUDGE_MODEL_DIR)", .serialized) struct LatencyTests {
    static let modelDirectory = ProcessInfo.processInfo.environment["AM_JUDGE_MODEL_DIR"].flatMap {
        $0.isEmpty ? nil : URL(fileURLWithPath: $0)
    }

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The committed VCTK starter clip (CC BY 4.0) as 16 kHz mono.
    static func clip(_ path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: repoRoot.appending(path: path))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1,
                                                interleaved: false))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                  frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: input)
        let converter = try #require(AVAudioConverter(from: file.processingFormat, to: target))
        let capacity = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024
        let output = try #require(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity))
        // The converter calls the block synchronously, inside `convert`; nothing here crosses a thread.
        nonisolated(unsafe) let source = input
        nonisolated(unsafe) var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return source
        }
        if let error { throw error }
        let channel = try #require(output.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    static func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    @Test("4 s starter phrase: median of 10 warm judge calls under 300 ms", .enabled(if: modelDirectory != nil))
    func latency() async throws {
        let folder = try #require(Self.modelDirectory)
        let judge = try await SoundJudge.load(folder: folder)
        let samples = try Self.clip("Resources/Starter/audio/vctk-013/p233.flac")
        let words = try ParityFixture.load("p233_013").expectedWords
        let bucket = try #require(judge.manifest.bucketSamples(for: samples.count))
        _ = try await judge.judge(samples: samples, words: words)  // warm up (first Neural Engine load)

        let clock = ContinuousClock()
        var forward: [Double] = [], scoring: [Double] = [], total: [Double] = []
        var last: SoundJudgement?
        for _ in 0..<10 {
            let t0 = clock.now
            last = try await judge.judge(samples: samples, words: words)
            total.append((clock.now - t0) / .milliseconds(1))
            let t1 = clock.now
            let posteriors = try await judge.forward(SoundJudge.modelInput(samples, bucket: bucket))
            let t2 = clock.now
            _ = SoundScorer.judge(posteriors, words: words, vocabulary: judge.vocabulary,
                                  takeSeconds: Double(samples.count) / 16_000)
            let t3 = clock.now
            forward.append((t2 - t1) / .milliseconds(1))
            scoring.append((t3 - t2) / .milliseconds(1))
        }
        let summary = String(format: "forward %.1f ms, GOP+scoring %.1f ms, total %.1f ms (median of 10; %.2f s take, %d-sample bucket)",
                             Self.median(forward), Self.median(scoring), Self.median(total),
                             Double(samples.count) / 16_000, bucket)
        print("SoundJudge latency: \(summary), model \(judge.modelID)")
        let judged = try #require(last)
        #expect(judged.words.count == words.count && judged.words.allSatisfy { !$0.phones.isEmpty })
        #expect(judged.words.allSatisfy { $0.youRange.map { $0.end <= Double(samples.count) / 16_000 + 1e-9 } ?? false })
        #if DEBUG
        print("SoundJudge latency: debug build, the 300 ms bar applies to `swift test -c release -Xswiftc -enable-testing`")
        #else
        #expect(Self.median(total) < 300, "\(summary)")
        #endif
    }

    @Test("takes out of range are refused before the model runs", .enabled(if: modelDirectory != nil))
    func outOfRange() async throws {
        let judge = try await SoundJudge.load(folder: try #require(Self.modelDirectory))
        let word = ExpectedWord(index: WordIndex(0), text: "a", variants: [["AH0"]])
        await #expect(throws: SoundJudgeError.takeOutOfRange(seconds: 0.05)) {
            _ = try await judge.judge(samples: [Float](repeating: 0, count: 800), words: [word])
        }
        await #expect(throws: SoundJudgeError.takeOutOfRange(seconds: 16)) {
            _ = try await judge.judge(samples: [Float](repeating: 0, count: 256_000), words: [word])
        }
        let none = try await judge.judge(samples: [Float](repeating: 0, count: 16_000),
                                         words: [ExpectedWord(index: WordIndex(0), text: "qx", variants: [])])
        #expect(none.words.map(\.state) == [.unjudged(.notInDictionary)])
    }

    @Test("scoring alone on the 4 s fixture (no model): median of 10, printed")
    func scoringOnly() throws {
        let fixture = try ParityFixture.load("p233_013")
        let posteriors = try fixture.posteriors()
        let words = fixture.expectedWords
        _ = SoundScorer.judge(posteriors, words: words)
        let clock = ContinuousClock()
        var times: [Double] = []
        for _ in 0..<10 {
            let t0 = clock.now
            _ = SoundScorer.judge(posteriors, words: words)
            times.append((clock.now - t0) / .milliseconds(1))
        }
        let units = fixture.units.count
        print(String(format: "SoundScorer: %.1f ms median for %d frames, %d units (unoptimised builds are slower)",
                     Self.median(times), fixture.frames, units))
    }

    @Test("without AM_JUDGE_MODEL_DIR the model checks are skipped", .enabled(if: modelDirectory == nil))
    func skippedWithoutModel() {
        print("SoundJudge latency: skipped; set AM_JUDGE_MODEL_DIR to a folder with manifest.json and LV60Int8.mlmodelc")
    }
}
