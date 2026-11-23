import Foundation
import Testing
import AMCore
import AMPitch

/// Per-frame F0 (nil: unvoiced) from a list of (count, Hz?) runs.
private func frames(_ runs: [(Int, Double?)]) -> [Double?] {
    runs.flatMap { count, hz in Array(repeating: hz, count: count) }
}

private func range(_ start: Double, _ end: Double) throws -> TimeRange { try TimeRange(start: start, end: end) }

@Suite("PitchTrack post-processing")
struct PitchTrackTests {
    @Test("voiced runs shorter than 30 ms are dropped, a 30 ms run is kept") func shortRunsDropped() {
        let track = PitchTrack(frameF0Hz: frames([(5, nil), (2, 300), (40, nil), (3, 200), (5, nil)]))
        #expect(track.voicedFrameCount == 3)
        #expect(abs(track.medianF0Hz! - 200) < 1e-9)
        #expect(track.segments.count == 1)
    }

    @Test("a one-frame spike is removed by the median filter") func spikeRemoved() {
        let track = PitchTrack(frameF0Hz: frames([(10, 200), (1, 260), (10, 200)]))
        #expect(track.allFrames.allSatisfy { abs($0.semitones) < 1e-9 })
    }

    @Test("a 30 ms run that jumps one octave is repaired", arguments: [440.0, 110.0])
    func octaveRunRepaired(jumpHz: Double) {
        let track = PitchTrack(frameF0Hz: frames([(20, 220), (3, jumpHz), (20, 220)]))
        #expect(track.voicedFrameCount == 43)
        #expect(track.allFrames.allSatisfy { abs($0.semitones) < 1e-9 })
    }

    @Test("an octave glide is not 'repaired'") func realGlideKept() {
        // 100 frames from 150 to 300 Hz (12 st/s): no frame is an octave from its neighbours.
        let hz = (0..<100).map { Optional(150 * pow(2, Double($0) / 99)) }
        let track = PitchTrack(frameF0Hz: hz)
        let semitones = track.allFrames.map(\.semitones)
        #expect(abs((semitones.last! - semitones.first!) - 12) < 0.2)
    }

    @Test("semitones are relative to the speaker's median F0") func semitonesReMedian() throws {
        let track = PitchTrack(frameF0Hz: frames([(30, 200), (20, 400)]))
        #expect(abs(track.medianF0Hz! - 200) < 1e-9)
        let st = track.allFrames.map(\.semitones)
        #expect(abs(st.first!) < 1e-9)
        #expect(abs(st.last! - 12) < 1e-9)
    }

    @Test("an unvoiced stretch up to 250 ms is bridged by interpolation, longer breaks the line",
          arguments: [(20, 1), (25, 1), (26, 2), (30, 2)])
    func bridgingAndBreaks(gapFrames: Int, expectedSegments: Int) {
        let track = PitchTrack(frameF0Hz: frames([(4, nil), (10, 200), (gapFrames, nil), (10, 400 / pow(2, 1.0 / 12))]))
        #expect(track.segments.count == expectedSegments)
        #expect(track.segments.first?.start == 0.04)
        if expectedSegments == 1 {
            let bridge = Array(track.allFrames[10..<(10 + gapFrames)])
            #expect(bridge.allSatisfy { !$0.voiced })
            let steps = zip(bridge, bridge.dropFirst()).map { $1.semitones - $0.semitones }
            #expect(steps.allSatisfy { abs($0 - steps[0]) < 1e-9 && $0 > 0 })
            #expect(track.allFrames.count == 20 + gapFrames)
        } else {
            #expect(track.segments.allSatisfy { $0.frames.allSatisfy(\.voiced) })
            #expect(abs(track.segments[1].start - Double(14 + gapFrames) * 0.01) < 1e-9)
        }
    }

    @Test("no voiced frames: empty, nil median, no NaN or 0 st",
          arguments: [[], [nil, nil, nil], [0, -5, .nan, .infinity, nil]] as [[Double?]])
    func emptyTrack(input: [Double?]) {
        let track = PitchTrack(frameF0Hz: input)
        #expect(track.isEmpty)
        #expect(track.medianF0Hz == nil)
        #expect(track.voicedFrameCount == 0)
        #expect(track.peakSemitones(in: try! range(0, 10)) == nil)
    }

    @Test("peakSemitones is nil with fewer than 3 voiced frames in the range") func peakNeedsThreeVoicedFrames() throws {
        // Frames 0-9 at 200 Hz, 10-14 unvoiced (bridged), 15-24 rising to 300 Hz.
        let rising = (0..<10).map { Optional(200 * pow(1.5, Double($0 + 1) / 10)) }
        let track = PitchTrack(frameF0Hz: frames([(10, 200), (5, nil)]) + rising)
        // Cells centred at 0.005, 0.015, …: [0.10, 0.155] holds only bridged frames.
        #expect(track.peakSemitones(in: try range(0.10, 0.155)) == nil)
        // [0.16, 0.18] holds two voiced cells (0.165, 0.175): too few.
        #expect(track.peakSemitones(in: try range(0.16, 0.18)) == nil)
        // [0.16, 0.19] holds three (frames 16–18); the peak is frame 18, 200 × 1.5^0.4 Hz.
        let three = try #require(track.peakSemitones(in: try range(0.16, 0.19)))
        let median = try #require(track.medianF0Hz)
        #expect(abs(three - 12 * log2(200 * pow(1.5, 0.4) / median)) < 1e-9)
        let whole = try #require(track.peakSemitones(in: try range(0, 1)))
        #expect(abs(whole - 12 * log2(300 / median)) < 1e-9)
    }
}

@Suite("PitchAxis")
struct PitchAxisTests {
    private func segment(peak: Double) -> [PitchSegment] {
        [PitchSegment(start: 0, frames: [PitchFrame(semitones: 0, voiced: true),
                                         PitchFrame(semitones: peak, voiced: true)])]
    }

    @Test("starts at ±12 st") func startsAtTwelve() {
        #expect(PitchAxis.extent(previous: nil, segments: []) == -12...12)
        #expect(PitchAxis.extent(previous: nil, segments: segment(peak: 11.9)) == -12...12)
        #expect(PitchAxis.extent(previous: nil, segments: segment(peak: -12)) == -12...12)
    }

    @Test("grows 12 → 18 → 24 and stops at 24") func grows() {
        let first = PitchAxis.extent(previous: nil, segments: segment(peak: 8))
        #expect(first == -12...12)
        let second = PitchAxis.extent(previous: first, segments: segment(peak: -14))
        #expect(second == -18...18)
        let third = PitchAxis.extent(previous: second, segments: segment(peak: 19))
        #expect(third == -24...24)
        #expect(PitchAxis.extent(previous: third, segments: segment(peak: 40)) == -24...24)
        #expect(PitchAxis.extent(previous: nil, segments: segment(peak: 23)) == -24...24)
    }

    @Test("never shrinks within a phrase") func neverShrinks() {
        var extent: ClosedRange<Double>? = nil
        var seen: [ClosedRange<Double>] = []
        for peak in [5.0, 13, 2, 0, 20, 1, 3] {
            extent = PitchAxis.extent(previous: extent, segments: segment(peak: peak))
            seen.append(extent!)
        }
        #expect(seen == [-12...12, -18...18, -18...18, -18...18, -24...24, -24...24, -24...24])
    }
}
