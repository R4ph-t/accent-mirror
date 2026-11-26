// Hand diagnostics for the sound judge on real audio (host only, never CI): runs the shipped path (16 kHz decode,
// `SoundJudgeWords.expected` from the starter phrase or a given text, `SoundJudge.load` + `judge`) on every clip listed
// in a manifest and writes one JSON line per clip with each word's chosen variant, every phone's GOP, P(error),
// confidence, flag and heard-instead, plus what samples went in. Skipped unless both variables are set:
//
//   AM_JUDGE_MODEL_DIR=<folder with manifest.json and LV60Int8.mlmodelc>
//   AM_JUDGE_DIAG_MANIFEST=<json: [{"name": "...", "audio": "/abs/path", "phrase": "vctk-012"} | {..., "text": "..."}]>
//   AM_JUDGE_DIAG_OUT=<output .jsonl> (default: next to the manifest)

import AMAlignment
import AMCore
import AMJudging
import AMLibrary
import AMPipeline
import Foundation
import Testing

@Suite("Sound judge take diagnostics (needs AM_JUDGE_MODEL_DIR and AM_JUDGE_DIAG_MANIFEST)")
struct SoundJudgeTakeDiagnostics {
    struct Item: Decodable {
        let name: String
        let audio: String
        let phrase: String?
        let text: String?
    }

    static let environment = ProcessInfo.processInfo.environment
    static let enabled = environment["AM_JUDGE_MODEL_DIR"] != nil && environment["AM_JUDGE_DIAG_MANIFEST"] != nil

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test("dump the judge on every listed clip", .enabled(if: enabled), .timeLimit(.minutes(20)))
    func dump() async throws {
        let folder = URL(fileURLWithPath: try #require(Self.environment["AM_JUDGE_MODEL_DIR"]))
        let manifestURL = URL(fileURLWithPath: try #require(Self.environment["AM_JUDGE_DIAG_MANIFEST"]))
        let outURL = Self.environment["AM_JUDGE_DIAG_OUT"].map { URL(fileURLWithPath: $0) }
            ?? manifestURL.deletingPathExtension().appendingPathExtension("out.jsonl")
        let items = try JSONDecoder().decode([Item].self, from: Data(contentsOf: manifestURL))
        let judge = try await SoundJudge.load(folder: folder)
        let dictionary = try PronouncingDictionary.bundled()
        let starter = Self.repoRoot.appending(path: "Resources/Starter")
        let references = try StarterReferences(
            manifest: try StarterManifest.load(from: starter, checkFiles: false), configuration: try .shipped())

        var lines: [String] = []
        for item in items {
            let samples = try StarterReferences.decode16k(URL(fileURLWithPath: item.audio))
            let words: [AMJudging.ExpectedWord]
            if let phrase = item.phrase {
                let input = try #require(references.phraseInput(PhraseID(phrase)), "\(phrase)")
                words = SoundJudgeWords.expected(input.words, dictionary: dictionary)
            } else {
                let text = try #require(item.text)
                words = text.split(separator: " ").enumerated().map { i, word in
                    AMJudging.ExpectedWord(
                        index: WordIndex(i), text: String(word),
                        variants: dictionary.pronunciations(of: WordText.fold(word)).map(\.phones))
                }
            }
            let peak = samples.map(abs).max() ?? 0
            let rms = (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))).squareRoot()
            let judgement = try await judge.judge(samples: samples, words: words)
            let wordRows: [[String: Any]] = judgement.words.map { word in
                var row: [String: Any] = ["index": word.index.rawValue, "text": word.text, "flagged": word.flagged]
                if let r = word.youRange { row["you"] = [r.start, r.end] }
                if let expected = words.first(where: { $0.index == word.index }) {
                    row["variants"] = expected.variants.map { $0.joined(separator: " ") }
                }
                row["phones"] = word.phones.map { phone -> [String: Any] in
                    var p: [String: Any] = [
                        "phone": phone.phone, "gop": phone.gop, "pError": 1 - phone.confidence,
                        "confidence": phone.confidence, "flagged": phone.flagged,
                    ]
                    switch phone.heardInstead {
                    case .sound(let token): p["heard"] = token
                    case .nothing: p["heard"] = "∅"
                    case nil: break
                    }
                    if let r = phone.youRange { p["you"] = [r.start, r.end] }
                    return p
                }
                return row
            }
            let line: [String: Any] = [
                "name": item.name, "samples": samples.count, "seconds": Double(samples.count) / 16_000,
                "sampleRate": 16_000, "peak": Double(peak), "rms": rms, "sha256": TakeAudio.sha256(of: samples),
                "bucket": judge.manifest.bucketSamples(for: samples.count) ?? -1,
                "threshold": judgement.errorThreshold, "modelID": judgement.modelID, "words": wordRows,
            ]
            let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
            lines.append(String(decoding: data, as: UTF8.self))
            let flagged = judgement.words.filter(\.flagged).map(\.text)
            print("judge diag: \(item.name) \(samples.count) samples, flagged \(flagged)")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: outURL, atomically: true, encoding: .utf8)
        print("judge diag: wrote \(outURL.path)")
    }
}
