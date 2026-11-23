// The PR-CI band-coverage golden (spec 09, Defaults): the coverage metric run end to end (pYIN, MFCC, DTW, pitch on
// model time, band, coverage) on the smoke set's six VCTK clips, as a deterministic regression golden. Never a rate
// gate, never an evaluation: the gate is the positive-set median, blocked on spec 24.
//
// The smoke set holds only held-out speakers' clips (p245, p288, p360 × phrases 002, 018) and no word timings, so
// each pair uses one comparable segment over the voiced span with edge anchors only (Poor, so DTW maps time), and the
// band is built from the other two smoke speakers of the phrase. The test speaker is never in its own band.
//
// Run with `AM_RECORD_GOLDEN=1` to print new values; paste them into `expected` only with a reason in the PR.

import AVFoundation
import Foundation
import Testing
import AMCore
import AMPitch
@testable import AMWarp

@Suite("Smoke-set band coverage golden") struct SmokeBandCoverageGolden {
    static let smoke = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/smoke/audio")
    static let speakers = ["p245", "p288", "p360"]
    static let phrases = ["002", "018"]

    /// Coverage per test clip, rounded to 4 decimals.
    static let expected: [String: Double] = [
        "p245_002": 0.5778, "p245_018": 0.2792, "p288_002": 0.331, "p288_018": 0.3316, "p360_002": 0.2535,
        "p360_018": 0.2973,
    ]

    struct Take {
        let id: String
        let sha256: String
        let track: PitchTrack
        let features: FrameFeatures
        /// First to last voiced frame.
        let span: TimeRange
    }

    static func load(_ id: String) async throws -> Take {
        let url = smoke.appendingPathComponent("vctk-\(id).flac")
        let data = try Data(contentsOf: url)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData)
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        let rate = file.processingFormat.sampleRate
        let track = try await PYINTracker().track(samples, sampleRate: rate)
        let first = try #require(track.segments.first)
        let last = try #require(track.segments.last)
        return Take(
            id: id, sha256: SHA256Digest.hex(of: data), track: track,
            features: FrameFeatures(samples: samples, sampleRate: rate),
            span: try TimeRange(
                start: first.start, end: last.start + Double(last.frames.count) * track.hopSeconds))
    }

    /// `take` onto `selected`: one comparable segment over both voiced spans, anchors Poor, refined by DTW.
    static func warp(_ take: Take, onto selected: Take) throws -> TimeWarp {
        let alignment = try WordAlignment(pairs: [.present(phrase: WordIndex(0), you: take.span)])
        return try TimeWarp(
            alignment: alignment, model: [TimedWord(range: selected.span, timing: .poor)],
            you: [WordIndex(0): TimedWord(range: take.span, timing: .poor)], timing: .good
        ).refined(model: selected.features, you: take.features)
    }

    @Test("Band coverage on the smoke set's VCTK clips matches the golden") func golden() async throws {
        var measured: [String: Double] = [:]
        for phrase in Self.phrases {
            var takes: [String: Take] = [:]
            for speaker in Self.speakers { takes[speaker] = try await Self.load("\(speaker)_\(phrase)") }
            for test in Self.speakers {
                let natives = Self.speakers.filter { $0 != test }.map { takes[$0]! }
                let selected = natives[0]
                let others = try natives.dropFirst().map {
                    WarpedVoice(voice: NativeVoice(sha256: $0.sha256, track: $0.track), ontoSelected: try Self.warp($0, onto: selected))
                }
                let t = takes[test]!
                let band = try NativeBand(
                    selected: NativeVoice(sha256: selected.sha256, track: selected.track), others: others,
                    testTake: t.sha256)
                let warp = try Self.warp(t, onto: selected)
                #expect(warp.timing == .rough)
                let coverage = try #require(band.coverage(of: warp.pitchOnModel(t.track), warp: warp))
                measured["\(test)_\(phrase)"] = (coverage * 10_000).rounded() / 10_000
            }
        }
        if ProcessInfo.processInfo.environment["AM_RECORD_GOLDEN"] == "1" {
            print("smoke band coverage golden:", measured.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", "))
        }
        for (id, value) in measured.sorted(by: { $0.key < $1.key }) {
            print("smoke band coverage \(id): \(value)")
        }
        #expect(measured == Self.expected)
    }
}
