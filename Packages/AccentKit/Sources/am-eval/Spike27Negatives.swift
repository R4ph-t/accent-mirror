// Spec 27 §1/§4: the training-side audio. Every tuning-side take goes through TD-PSOLA with an identity modification
// (CTO markup 4) and is re-measured; every multi-syllable native word gives one synthetic misplaced-stress negative
// (the stressed nucleus and one unstressed nucleus swap duration, intensity and f0 contour), re-measured through the
// same front end. Only features are kept (no audio), except the 20 spot-check negatives written to listen/.

import AMAlignment
import AMCore
import AMEvaluation
import AMPitch
import AMSpike27
import AMTimestampEval
import Foundation

struct SpikeNegative: Codable, Sendable {
    /// "<clip>#<word index>".
    let id: String
    let clip: String
    let speaker: String
    let population: Population
    let word: Int
    let target: Int
    let swapped: Int
    let syllables: Int
    let measured: MeasuredAudio
    /// The take's oracle words carried through the time map.
    let words: [TimedWord]
    /// Reported control: the negative swapped back by a second PSOLA pass (original prosody, two passes of PSOLA
    /// artefacts in the swapped regions), re-measured; its words are the original oracle words.
    let roundTrip: MeasuredAudio
}

struct SpikeIdentity: Codable, Sendable {
    let clip: String
    let measured: MeasuredAudio
}

struct NegativesFile: Codable {
    let seed: UInt64
    let identity: [SpikeIdentity]
    let negatives: [SpikeNegative]
    let sourceWords: Int
    let dropped: [String: Int]
    /// Swaps whose duration factor is outside [0.5, 2] (kept; PSOLA quality falls off there).
    let extremeDurationRatio: Int
    let listen: [String]
}

enum SpikeNegatives {
    static let minimumCoverage = 0.9

    struct Work: Sendable {
        let identity: SpikeIdentity
        let negatives: [SpikeNegative]
        let dropped: [String: Int]
        let sourceWords: Int
        let extreme: Int
    }

    static func stripped(_ m: MeasuredAudio) -> MeasuredAudio {
        MeasuredAudio(duration: m.duration, nuclei: m.nuclei, voicedTimes: [], voicedSemitones: [], hopSeconds: m.hopSeconds)
    }

    /// The unstressed syllable a word's negative swaps with: the split manifest's seed, per clip and word.
    static func swapIndex(seed: UInt64, clip: String, word: Int, syllables: Int, target: Int) -> Int {
        var random = Jitter.SplitMix64(state: seed ^ Jitter.fnv1a64("\(clip)#\(word)#negative"))
        let candidates = (0..<syllables).filter { $0 != target }
        return candidates[Int(random.next() % UInt64(candidates.count))]
    }

    struct Built: Sendable {
        let output: PSOLA.Output
        let regions: [PSOLA.Region]
        let source: [Float]
        let identity: [Float]
    }

    /// One clip: its identity pass and its negatives.
    static func process(_ clip: SpikeClip, seed: UInt64) async throws -> Work {
        let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(fileURLWithPath: clip.audio))
        let track = try await PYINTracker(thresholds: Thresholds.current.pitch).track(samples, sampleRate: FrontEnd.sampleRate)
        let marks = PSOLA.analysisMarks(samples, track: track, sampleRate: FrontEnd.sampleRate)
        let identity = PSOLA.process(samples, marks: marks, regions: [], sampleRate: FrontEnd.sampleRate)
        let identityMeasured = try await FrontEnd.measure(identity.samples)
        let raw = clip.measured
        let words = clip.words(.oracle) ?? []
        var negatives: [SpikeNegative] = []
        var dropped: [String: Int] = [:]
        var sources = 0
        var extreme = 0
        for word in words {
            guard let target = word.target, word.syllables >= 2 else { continue }
            sources += 1
            guard let list = ArmSelection.topK(raw.nuclei, start: word.start, end: word.end, count: word.syllables,
                                               paddingSeconds: 0) else {
                dropped["front end found fewer than N nuclei", default: 0] += 1
                continue
            }
            let u = swapIndex(seed: seed, clip: clip.id, word: word.index, syllables: word.syllables, target: target)
            let s = raw.nuclei[list[target]], v = raw.nuclei[list[u]]
            let regions = StressSwap.regions(stressed: s, unstressed: v, take: raw)
            let coverage = min(
                PSOLA.markCoverage(s.regionStart...s.regionEnd, marks: marks, track: track, sampleRate: FrontEnd.sampleRate),
                PSOLA.markCoverage(v.regionStart...v.regionEnd, marks: marks, track: track, sampleRate: FrontEnd.sampleRate))
            guard coverage >= minimumCoverage else {
                dropped["pitch-mark coverage < 90% of the voiced span", default: 0] += 1
                continue
            }
            let output = PSOLA.process(samples, marks: marks, regions: regions, sampleRate: FrontEnd.sampleRate)
            guard !output.clipped else {
                dropped["clipping", default: 0] += 1
                continue
            }
            if regions.contains(where: { $0.durationFactor < 0.5 || $0.durationFactor > 2 }) { extreme += 1 }
            let measured = try await FrontEnd.measure(output.samples)
            let moved = words.map { $0.moved(start: output.timeMap.forward($0.start), end: output.timeMap.forward($0.end)) }
            let back = try await roundTrip(output, regions: regions)
            negatives.append(SpikeNegative(
                id: "\(clip.id)#\(word.index)", clip: clip.id, speaker: clip.speaker, population: clip.population,
                word: word.index, target: target, swapped: u, syllables: word.syllables, measured: stripped(measured),
                words: moved, roundTrip: stripped(back)))
        }
        return Work(identity: SpikeIdentity(clip: clip.id, measured: stripped(identityMeasured)), negatives: negatives,
                    dropped: dropped, sourceWords: sources, extreme: extreme)
    }

    /// The negative swapped back: each region, at its place on the negative's timeline, gets the inverse duration
    /// factor, gain and shift, through a fresh analysis of the negative (its own pYIN marks).
    static func roundTrip(_ output: PSOLA.Output, regions: [PSOLA.Region]) async throws -> MeasuredAudio {
        let samples = output.samples
        let track = try await PYINTracker(thresholds: Thresholds.current.pitch).track(samples, sampleRate: FrontEnd.sampleRate)
        let marks = PSOLA.analysisMarks(samples, track: track, sampleRate: FrontEnd.sampleRate)
        let inverse = regions.map {
            PSOLA.Region(start: output.timeMap.forward($0.start), end: output.timeMap.forward($0.end),
                         durationFactor: 1 / $0.durationFactor, gainDB: -$0.gainDB, shiftProfile: $0.shiftProfile.map { -$0 })
        }
        let back = PSOLA.process(samples, marks: marks, regions: inverse, sampleRate: FrontEnd.sampleRate)
        return FrontEnd.measure(back.samples, track: try await PYINTracker(thresholds: Thresholds.current.pitch)
            .track(back.samples, sampleRate: FrontEnd.sampleRate))
    }

    /// The audio of one negative, its source and its identity pass (for listen/).
    static func audio(_ clip: SpikeClip, negative: SpikeNegative) async throws -> Built {
        let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(fileURLWithPath: clip.audio))
        let track = try await PYINTracker(thresholds: Thresholds.current.pitch).track(samples, sampleRate: FrontEnd.sampleRate)
        let marks = PSOLA.analysisMarks(samples, track: track, sampleRate: FrontEnd.sampleRate)
        let identity = PSOLA.process(samples, marks: marks, regions: [], sampleRate: FrontEnd.sampleRate)
        let word = (clip.words(.oracle) ?? []).first { $0.index == negative.word }!
        let list = ArmSelection.topK(clip.measured.nuclei, start: word.start, end: word.end, count: word.syllables,
                                     paddingSeconds: 0)!
        let regions = StressSwap.regions(stressed: clip.measured.nuclei[list[negative.target]],
                                         unstressed: clip.measured.nuclei[list[negative.swapped]], take: clip.measured)
        let output = PSOLA.process(samples, marks: marks, regions: regions, sampleRate: FrontEnd.sampleRate)
        return Built(output: output, regions: regions, source: samples, identity: identity.samples)
    }

    static func writeWAV(_ samples: [Float], to url: URL, sampleRate: Int = 16_000) throws {
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes)); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        for s in samples { append(Int16(max(-1, min(1, s)) * 32_767)) }
        try data.write(to: url)
    }
}

func spike27Negatives(_ env: SpikeEnvironment) async throws {
    let url = env.file("negatives.json")
    if FileManager.default.fileExists(atPath: url.path) {
        spikeLog("spike27 negatives: cached (\(url.path))")
        return
    }
    let seed = env.split.foldSeed
    let clips = try await SpikeData.clips(.tuningVCTK, env: env, log: spikeLog)
        + SpikeData.clips(.tts, env: env, log: spikeLog)
    try Spike27Guard.checkTraining(clips.map { ($0.population, $0.speaker) }, split: env.split, use: "negatives")
    spikeLog("spike27 negatives: \(clips.count) tuning-side takes (seed \(seed))")
    let started = Date()
    var results: [Int: SpikeNegatives.Work] = [:]
    try await withThrowingTaskGroup(of: (Int, SpikeNegatives.Work).self) { group in
        var next = 0
        func add() {
            guard next < clips.count else { return }
            let index = next, clip = clips[index]
            next += 1
            group.addTask { (index, try await SpikeNegatives.process(clip, seed: seed)) }
        }
        for _ in 0..<max(1, env.jobs) { add() }
        while let (index, work) = try await group.next() {
            results[index] = work
            if results.count % 100 == 0 {
                spikeLog(String(format: "spike27 negatives: %d/%d takes (%.0f s)", results.count, clips.count,
                                Date().timeIntervalSince(started)))
            }
            add()
        }
    }
    let works = results.keys.sorted().map { results[$0]! }
    var dropped: [String: Int] = [:]
    for w in works { for (k, v) in w.dropped { dropped[k, default: 0] += v } }
    let negatives = works.flatMap(\.negatives)

    // The 20 spot-check negatives (taste call, Raph): evenly spaced over the accepted negatives in id order, VCTK only.
    let pool = negatives.filter { $0.population == .tuningVCTK }.sorted { $0.id < $1.id }
    let picks = (0..<min(20, pool.count)).map { pool[$0 * pool.count / min(20, pool.count)] }
    try FileManager.default.createDirectory(at: env.listen, withIntermediateDirectories: true)
    var index = ["# Spec 27 spot-check negatives (taste call, Raph)", "",
                 "TD-PSOLA prosody transplantation (spec 27 §4). Each negative sits next to its raw source and its identity-processed version (same pitch marks, no swap). 16 kHz mono. Syllables are 0-based in the word's CMUdict pronunciation; the target is CMUdict primary stress.", "",
                 "| # | word | speaker | clip | target syllable | swapped with | raw | identity | negative |", "|---|---|---|---|---|---|---|---|---|"]
    let byID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
    var names: [String] = []
    for (n, negative) in picks.enumerated() {
        let clip = byID[negative.clip]!
        let built = try await SpikeNegatives.audio(clip, negative: negative)
        let word = (clip.words(.oracle) ?? []).first { $0.index == negative.word }!.text
        let stem = String(format: "%02d-%@-%@", n + 1, negative.clip, word.lowercased().filter(\.isLetter))
        try SpikeNegatives.writeWAV(built.source, to: env.listen.appendingPathComponent("\(stem)-raw.wav"))
        try SpikeNegatives.writeWAV(built.identity, to: env.listen.appendingPathComponent("\(stem)-identity.wav"))
        try SpikeNegatives.writeWAV(built.output.samples, to: env.listen.appendingPathComponent("\(stem)-negative.wav"))
        index.append("| \(n + 1) | \(word) | \(negative.speaker) | \(negative.clip) | \(negative.target) | \(negative.swapped) | "
                     + "\(stem)-raw.wav | \(stem)-identity.wav | \(stem)-negative.wav |")
        names.append(stem)
    }
    try (index.joined(separator: "\n") + "\n").write(to: env.listen.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    let status = env.work.deletingLastPathComponent().appendingPathComponent("logs/status.txt")
    try FileManager.default.createDirectory(at: status.deletingLastPathComponent(), withIntermediateDirectories: true)
    let line = "LISTEN READY: \(env.listen.standardizedFileURL.path)\n"
    if let handle = try? FileHandle(forWritingTo: status) {
        handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try handle.close()
    } else {
        try line.write(to: status, atomically: true, encoding: .utf8)
    }
    spikeLog("spike27 negatives: wrote \(picks.count) spot-check negatives to \(env.listen.path); \(line)")

    let file = NegativesFile(seed: seed, identity: works.map(\.identity), negatives: negatives,
                             sourceWords: works.reduce(0) { $0 + $1.sourceWords }, dropped: dropped,
                             extremeDurationRatio: works.reduce(0) { $0 + $1.extreme }, listen: names)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(file).write(to: url)
    spikeLog("spike27 negatives: \(file.sourceWords) source words → \(negatives.count) negatives; dropped \(dropped); "
             + "duration factor outside [0.5, 2]: \(file.extremeDurationRatio) (\(Int(Date().timeIntervalSince(started))) s)")
}
