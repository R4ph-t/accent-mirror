// The comparison behind scripts/pitch-real-clips.sh (spec 04, Open question 1). Runs only when the script sets
// AM_PITCH_REAL_CLIPS_MANIFEST (lines: label, 16 kHz mono wav path, Praat output path), so never in `make check` or CI.

import AVFoundation
import Foundation
import Testing
import AMCore
import AMPitch

private let manifestPath = ProcessInfo.processInfo.environment["AM_PITCH_REAL_CLIPS_MANIFEST"]

/// Gross pitch error: more than 20% off Praat.
private let grossErrorRatio = 0.2
/// Pass: gross errors under 5% of frames both call voiced, voicing agreement at least 90% of frames.
private let maxGrossErrorShare = 0.05
private let minVoicingAgreement = 0.90

@Suite("Real-clip comparison with Praat", .enabled(if: manifestPath != nil))
struct RealClipComparison {
    struct Row {
        let label: String
        let bothVoiced: Int
        let grossErrorShare: Double
        let voicingAgreement: Double
        var passes: Bool { bothVoiced > 0 && grossErrorShare < maxGrossErrorShare && voicingAgreement >= minVoicingAgreement }
    }

    @Test("pyin-1 against Praat's autocorrelation pitch") func compare() async throws {
        let manifest = try String(contentsOfFile: try #require(manifestPath), encoding: .utf8)
        var rows: [Row] = []
        for line in manifest.split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            try #require(fields.count == 3)
            let samples = try loadMono16k(fields[1])
            let track = try await PYINTracker().track(samples, sampleRate: 16_000)
            let praat = try loadPraat(fields[2])
            rows.append(compare(label: fields[0], track: track, frameCount: samples.count / 160, praat: praat))
        }
        print("clip | frames both voiced | gross pitch error | voicing agreement | result")
        print("---- | --- | --- | --- | ---")
        for row in rows {
            print(String(format: "%@ | %d | %.1f%% | %.1f%% | %@", row.label, row.bothVoiced,
                         row.grossErrorShare * 100, row.voicingAgreement * 100, row.passes ? "PASS" : "FAIL"))
        }
        let pass = rows.count == 3 && rows.allSatisfy(\.passes)
        print("pitch real clips: \(pass ? "PASS" : "FAIL") (gross error < 5%, voicing agreement ≥ 90%, per clip)")
        #expect(pass)
    }

    /// Our per-frame voicing and F0 (bridged frames are unvoiced) against Praat's frame nearest each cell centre.
    private func compare(label: String, track: PitchTrack, frameCount: Int, praat: [(time: Double, f0: Double)]) -> Row {
        var ours = [Double?](repeating: nil, count: frameCount)
        if let median = track.medianF0Hz {
            for segment in track.segments {
                let first = Int((segment.start / track.hopSeconds).rounded())
                for (k, frame) in segment.frames.enumerated() where frame.voiced && first + k < frameCount {
                    ours[first + k] = median * pow(2, frame.semitones / 12)
                }
            }
        }
        var agree = 0, compared = 0, bothVoiced = 0, gross = 0
        for (i, f0) in ours.enumerated() {
            let centre = (Double(i) + 0.5) * track.hopSeconds
            guard let nearest = praat.min(by: { abs($0.time - centre) < abs($1.time - centre) }),
                  abs(nearest.time - centre) <= track.hopSeconds else { continue }
            compared += 1
            let praatVoiced = nearest.f0 > 0
            if praatVoiced == (f0 != nil) { agree += 1 }
            if let f0, praatVoiced {
                bothVoiced += 1
                if abs(f0 / nearest.f0 - 1) > grossErrorRatio { gross += 1 }
            }
        }
        return Row(label: label, bothVoiced: bothVoiced,
                   grossErrorShare: bothVoiced > 0 ? Double(gross) / Double(bothVoiced) : 1,
                   voicingAgreement: compared > 0 ? Double(agree) / Double(compared) : 0)
    }

    private func loadPraat(_ path: String) throws -> [(time: Double, f0: Double)] {
        try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 2, let t = Double(parts[0]), let f = Double(parts[1]) else { return nil }
            return (t, f)
        }
    }

    /// Reads the 16 kHz mono WAV the Praat script saved.
    private func loadMono16k(_ path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        try #require(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData)
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }
}
