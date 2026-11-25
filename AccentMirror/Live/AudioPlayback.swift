@preconcurrency import AVFAudio
import Foundation

/// Plays a `PlaybackSchedule` (Play Model, Play You, Play Both, a word loop) through `AVAudioEngine` (v1 §5.3, v3
/// §3.5). The schedule is rendered into one 16 kHz buffer, each step padded or cut to its scheduled length, so the
/// audio and the playhead (`PlaybackRun` on the system clock) stay together. A loop repeats the buffer until Esc.
/// The engine runs only while something plays: the output device isn't held between plays.
@MainActor
final class AudioPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: AudioClip.sampleRate, channels: 1)
    private var generation = 0

    init() {
        engine.attach(player)
        if let format { engine.connect(player, to: engine.mainMixerNode, format: format) }
    }

    /// The samples `schedule` plays, end to end: each side's slice of its clip (its timeline is the clip's window),
    /// silence for a pause or a side with no audio.
    nonisolated static func render(_ schedule: PlaybackSchedule, model: AudioClip?, you: AudioClip?) -> [Float] {
        let rate = AudioClip.sampleRate
        var out: [Float] = []
        for step in schedule.steps {
            let wanted = Int((step.seconds * rate).rounded())
            var chunk: [Float] = []
            if case .play(let side, _, let from, let to) = step, let clip = side == .model ? model : you {
                // from == to == 1 is the tail after the last word: clip.end ..< playbackEnd.
                let a = from == 1 && to == 1 ? clip.end : clip.start + from * clip.seconds
                let b = to == 1 ? clip.playbackEnd : clip.start + to * clip.seconds
                let i0 = max(0, min(clip.samples.count, Int((a * rate).rounded())))
                let i1 = max(i0, min(clip.samples.count, Int((b * rate).rounded())))
                chunk = Array(clip.samples[i0..<i1])
                fade(&chunk, seconds: schedule.fadeSeconds, rate: rate)
            }
            if chunk.count < wanted { chunk += [Float](repeating: 0, count: wanted - chunk.count) }
            out += chunk.prefix(wanted)
        }
        return out
    }

    /// A linear ramp over the first and last `seconds` of `chunk` (v5: 10 ms on word and sound buttons).
    nonisolated static func fade(_ chunk: inout [Float], seconds: Double, rate: Double) {
        let length = min(chunk.count / 2, Int((seconds * rate).rounded()))
        guard length > 0 else { return }
        for i in 0..<length {
            let gain = Float(i) / Float(length)
            chunk[i] *= gain
            chunk[chunk.count - 1 - i] *= gain
        }
    }

    func play(_ schedule: PlaybackSchedule, model: AudioClip?, you: AudioClip?) {
        stop()
        let samples = Self.render(schedule, model: model, you: you)
        guard let format, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            return
        }
        generation += 1
        let generation = self.generation
        player.scheduleBuffer(buffer, at: nil, options: schedule.repeats ? .loops : [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.stop()
            }
        }
        player.play()
    }

    func stop() {
        generation += 1
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
    }
}
