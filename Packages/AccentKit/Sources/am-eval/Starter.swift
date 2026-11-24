// Spec 15: builds `Resources/Starter/` from CPO's phrase table (fixtures/starter/phrases.json), the pinned VCTK 0.92
// clips (eval-speakers.json SHA-256s), spec 02's trim and the recorded WhisperKit word timings. Regenerates the whole
// folder; two runs give byte-identical files. No ASR, no network.

import AMAlignment
import AMCore
import AMEvaluation
import AMLibrary
import AMPipeline
import Foundation

/// CPO's content, as committed: packs in order, and per shared-text prompt its text and overrides. Every override is
/// a target (CPO gives one for each target), so `targets` is the overrides' word indices.
struct StarterPhraseTable: Decodable {
    struct Pack: Decodable {
        let id: String
        let title: String
        let phrases: [String]
    }
    struct Phrase: Decodable {
        let text: String
        let pronunciations: [Int: String]
        var targets: [Int] { pronunciations.keys.sorted() }
    }
    let corpus: String
    let voices: [String]
    let packs: [Pack]
    let phrases: [String: Phrase]
}

/// A bundled voice in eval-speakers.json, with the fields the manifest copies (spec 15, Addendum r6 E7).
struct BundledVoice: Decodable {
    let speaker: String
    let accent: String
    let region: String
    let gender: String
    /// Phrase id → SHA-256 of the official `{speaker}_{phrase}_mic1.flac`.
    let files: [String: String]
}

func starterBuild(_ args: Arguments) async throws -> Int32 {
    let root = try repositoryRoot()
    let table = try JSONDecoder().decode(
        StarterPhraseTable.self, from: Data(contentsOf: try args.url("phrases")))
    struct Speakers: Decodable { let bundled: [BundledVoice] }
    let speakers = try JSONDecoder().decode(Speakers.self, from: Data(contentsOf: try args.url("eval-speakers")))
    let raw = try args.url("raw")
    let timingsDir = try args.url("timings")
    let out = try args.url("out")
    let pin = try JSONSerialization.jsonObject(
        with: Data(contentsOf: root.appendingPathComponent("fixtures/corpora/vctk.pin.json"))) as? [String: String] ?? [:]
    let sourceURL = pin["landingPage"] ?? "https://datashare.ed.ac.uk/handle/10283/3443"
    let timings = try FixtureTimestamper(directory: timingsDir)
    let bundled = Dictionary(uniqueKeysWithValues: speakers.bundled.map { ($0.speaker, $0) })
    guard table.voices.allSatisfy({ bundled[$0] != nil && !VCTK.excludedSpeakers.contains($0) }) else {
        throw CLIError.failed("phrase table voices must be eval-speakers.json's bundled voices, never p280 or p315")
    }

    // The whole folder is regenerated.
    let fm = FileManager.default
    for folder in ["audio", "timings", "analysis"] { try? fm.removeItem(at: out.appendingPathComponent(folder)) }
    try fm.createDirectory(at: out, withIntermediateDirectories: true)

    let rule = TrimRule()
    var kept: [String] = []
    var dropped: [String] = []
    var leftOut: [String] = []
    var phrases: [StarterManifest.Phrase] = []
    for prompt in table.phrases.keys.sorted() {
        let phrase = table.phrases[prompt]!
        let id = PhraseID("vctk-" + prompt)
        let headline = VCTK.headlineReference(for: prompt)
        let voices = [headline] + table.voices.filter { $0 != headline && VCTK.nativeReaders(for: prompt).contains($0) }
        var recordings: [StarterManifest.Recording] = []
        for speaker in voices {
            let entry = bundled[speaker]!
            let utterance = "\(speaker)_\(prompt)"
            guard let pinned = entry.files[prompt] else {
                leftOut.append("\(utterance): not in VCTK 0.92")
                if speaker == headline { break }
                continue
            }
            let source = raw.appendingPathComponent("\(speaker)/\(utterance)_mic1.flac")
            guard (try? sha256(of: source)) == pinned else {
                throw CLIError.failed("\(source.path): missing or SHA-256 differs from eval-speakers.json; run scripts/fetch-vctk-eval.sh")
            }
            let (samples, rate) = try AudioFiles.readMono(source)
            guard case .keep(let range) = rule.apply(samples: samples, sampleRate: rate) else {
                let why: String = switch rule.apply(samples: samples, sampleRate: rate) {
                case .outOfRange(let seconds): String(format: "%.2f s outside 2–6 s", seconds)
                default: "no speech"
                }
                if speaker == headline {
                    dropped.append("\(prompt) (headline \(speaker): \(why))")
                    recordings = []
                    break
                }
                leftOut.append("\(utterance): trim \(why)")
                continue
            }
            guard let recorded = timings.recording(for: utterance), recorded.audioSHA256 == pinned else {
                leftOut.append("\(utterance): no recorded word timings for the pinned clip")
                if speaker == headline { break }
                continue
            }
            let trimStart = Double(range.lowerBound) / rate
            let trimEnd = Double(range.upperBound) / rate
            let duration = trimEnd - trimStart
            let audioPath = "audio/\(id.rawValue)/\(speaker).flac"
            let audioURL = out.appendingPathComponent(audioPath)
            try fm.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AudioFiles.writeFLAC(Array(samples[range]), sampleRate: rate, to: audioURL)
            let audioSHA = try sha256(of: audioURL)
            // The recorded words, moved onto the trimmed clip and kept inside it.
            func shifted(_ t: Double) -> Double { (min(max(t - trimStart, 0), duration) * 1e6).rounded() / 1e6 }
            let words = recorded.words.map {
                WordTimestamp(word: $0.word, start: shifted($0.start), end: shifted($0.end), probability: $0.probability)
            }
            let shiftedTimings = RecordedTimestamps(
                clipID: utterance, audioSHA256: audioSHA, asrModelID: recorded.asrModelID, text: recorded.text,
                words: words)
            let timingsPath = "timings/\(id.rawValue)/\(speaker).json"
            let timingsURL = out.appendingPathComponent(timingsPath)
            try fm.createDirectory(at: timingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try prettyJSON(shiftedTimings).write(to: timingsURL)
            recordings.append(StarterManifest.Recording(
                id: RecordingID(utterance), speaker: speaker, accent: entry.accent, region: entry.region,
                gender: entry.gender, corpus: table.corpus, licence: "CC BY 4.0", sourceURL: sourceURL,
                utteranceID: utterance, sourceFile: "wav48_silence_trimmed/\(speaker)/\(utterance)_mic1.flac",
                trimStart: (trimStart * 1e6).rounded() / 1e6, trimEnd: (trimEnd * 1e6).rounded() / 1e6,
                audio: audioPath, audioSHA256: audioSHA, timings: timingsPath,
                timingsSHA256: try sha256(of: timingsURL), analysis: "analysis/\(id.rawValue)/\(speaker).json",
                analysisSHA256: "", analysisKey: ""))
        }
        guard recordings.first?.speaker == headline else {
            if !dropped.contains(where: { $0.hasPrefix(prompt) }) { dropped.append("\(prompt) (headline \(headline) unavailable)") }
            for folder in ["audio", "timings"] { try? fm.removeItem(at: out.appendingPathComponent("\(folder)/\(id.rawValue)")) }
            continue
        }
        kept.append(prompt)
        phrases.append(StarterManifest.Phrase(
            id: id, text: phrase.text, targets: phrase.targets, pronunciations: phrase.pronunciations,
            headlineVoice: recordings[0].id, recordings: recordings))
    }
    let keptIDs = Set(kept)
    let packs = table.packs.map { pack in
        StarterManifest.Pack(
            id: pack.id, title: pack.title,
            phrases: pack.phrases.filter { keptIDs.contains($0) }.map { PhraseID("vctk-" + $0) })
    }
    let asrModelID = timings.asrModelID

    // Analyses: the pipeline's own rebuild path, so the CI check recomputes exactly this.
    let draft = StarterManifest(asrModelID: asrModelID, packs: packs, phrases: phrases)
    let references = try StarterReferences(manifest: draft, configuration: try .shipped())
    var final: [StarterManifest.Phrase] = []
    for phrase in phrases {
        var recordings: [StarterManifest.Recording] = []
        for r in phrase.recordings {
            let source = StarterRecordingSource(
                phrase: phrase, recording: r, audio: out.appendingPathComponent(r.audio),
                timings: out.appendingPathComponent(r.timings), asrModelID: asrModelID)
            let record = try await references.analyse(source)
            let url = out.appendingPathComponent(r.analysis)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try record.bytes.write(to: url)
            recordings.append(StarterManifest.Recording(
                id: r.id, speaker: r.speaker, accent: r.accent, region: r.region, gender: r.gender, corpus: r.corpus,
                licence: r.licence, sourceURL: r.sourceURL, utteranceID: r.utteranceID, sourceFile: r.sourceFile,
                trimStart: r.trimStart, trimEnd: r.trimEnd, audio: r.audio, audioSHA256: r.audioSHA256,
                timings: r.timings, timingsSHA256: r.timingsSHA256, analysis: r.analysis,
                analysisSHA256: SHA256Digest.hex(of: record.bytes), analysisKey: record.key))
        }
        final.append(StarterManifest.Phrase(
            id: phrase.id, text: phrase.text, targets: phrase.targets, pronunciations: phrase.pronunciations,
            headlineVoice: phrase.headlineVoice, recordings: recordings))
        print("starter: \(phrase.id) analysed \(recordings.count) recordings")
    }
    let manifest = StarterManifest(asrModelID: asrModelID, packs: packs, phrases: final)
    if let problem = manifest.problems().first { throw CLIError.failed("manifest: \(problem)") }
    try manifest.encoded().write(to: out.appendingPathComponent(StarterManifest.fileName))
    try attribution(manifest, speakers: table.voices.compactMap { bundled[$0] })
        .write(to: out.appendingPathComponent("ATTRIBUTION.md"), atomically: true, encoding: .utf8)
    if let problem = manifest.fileProblems(in: out).first { throw CLIError.failed("files: \(problem)") }

    print("starter: kept \(kept.count) phrases: \(kept.joined(separator: ", "))")
    print("starter: dropped \(dropped.count) phrases: \(dropped.joined(separator: "; "))")
    print("starter: voices left out (\(leftOut.count)): \(leftOut.joined(separator: "; "))")
    for pack in packs { print("starter: pack \(pack.title): \(pack.phrases.map(\.rawValue).joined(separator: ", "))") }
    print("starter: \(final.flatMap(\.recordings).count) recordings")
    return 0
}

private func prettyJSON(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    return try encoder.encode(value) + Data("\n".utf8)
}

private func attribution(_ manifest: StarterManifest, speakers: [BundledVoice]) -> String {
    var lines = [
        "# Starter recordings: attribution",
        "",
        "The native recordings in this folder are cut from the CSTR VCTK Corpus 0.92:",
        "",
        "Christophe Veaux, Junichi Yamagishi, Kirsten MacDonald, \"CSTR VCTK Corpus: English Multi-speaker Corpus for",
        "CSTR Voice Cloning Toolkit (version 0.92)\", The Centre for Speech Technology Research (CSTR), University of",
        "Edinburgh. https://doi.org/10.7488/ds/2645. Licensed under CC BY 4.0",
        "(https://creativecommons.org/licenses/by/4.0/).",
        "",
        "Changes: each clip (`wav48_silence_trimmed/<speaker>/<utterance>_mic1.flac`) was trimmed to the speech with",
        "200 ms before and 300 ms after it (the same rule for every speaker; `trimStart`/`trimEnd` in `manifest.json`)",
        "and re-encoded as mono 16-bit FLAC at its source rate. The word timings were recognised by WhisperKit",
        "(`\(manifest.asrModelID)`) and shifted onto the trimmed clip; the analyses are derived from both.",
        "",
        "| Speaker | Accent | Region | Gender | Utterances |",
        "|---|---|---|---|---|",
    ]
    for speaker in speakers {
        let utterances = manifest.phrases.flatMap(\.recordings).filter { $0.speaker == speaker.speaker }.map(\.utteranceID)
        guard !utterances.isEmpty else { continue }
        lines.append("| \(speaker.speaker) | \(speaker.accent) | \(speaker.region) | \(speaker.gender) | \(utterances.joined(separator: ", ")) |")
    }
    return lines.joined(separator: "\n") + "\n"
}
