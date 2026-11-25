// The starter regression (sound-judging plan, 2026-11-25): the 14 starter references of the shipped default voice
// (p311), judged as if they were your takes, flag at most one word in total. Natives should be clean. The bar is fixed:
// a failure is reported with the flagged words, never tuned away.
//
// CI runs it without the model on committed posteriors (fixtures/starter-judge, written by
// tools/make_starter_judge_fixtures.py: the blank and English espeak columns as float16; every other column gets the
// fixture's fill). A host-only variant runs the real model when AM_JUDGE_MODEL_DIR names its folder.

import AMAlignment
import AMCore
import AMJudging
import AMLibrary
import AMPipeline
import Foundation
import Testing

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
private let starterFolder = repoRoot.appending(path: "Resources/Starter")
private let fixtureFolder = repoRoot.appending(path: "fixtures/starter-judge")
private let defaultVoice = "p311"
private let flaggedWordBar = 1

/// One committed fixture: a phrase's p311 posteriors, compacted.
private struct StarterJudgeFixture: Decodable {
    let phraseID: String
    let recordingID: String
    let frames: Int
    let vocabularySize: Int
    let columns: [Int]
    let fill: Float
    let valuesFloat16Base64: String

    var posteriors: LogPosteriors {
        get throws {
            let bytes = try #require(Data(base64Encoded: valuesFloat16Base64))
            #expect(bytes.count == frames * columns.count * 2, "\(phraseID): fixture size")
            var values = [Float](repeating: fill, count: frames * vocabularySize)
            bytes.withUnsafeBytes { raw in
                for frame in 0..<frames {
                    for (k, column) in columns.enumerated() {
                        let bits = raw.loadUnaligned(fromByteOffset: (frame * columns.count + k) * 2, as: UInt16.self)
                        values[frame * vocabularySize + column] = Float(Float16(bitPattern: UInt16(littleEndian: bits)))
                    }
                }
            }
            return LogPosteriors(frames: frames, vocabularySize: vocabularySize, values: values)
        }
    }
}

@Suite("Starter sound-judging regression") struct StarterJudgeRegressionTests {
    /// Every starter phrase, its p311 recording and the phrase's expected words, as the analyzer builds them.
    static func starterPhrases() throws -> [(phrase: StarterManifest.Phrase, audio: URL, words: [AMJudging.ExpectedWord])] {
        let manifest = try StarterManifest.load(from: starterFolder, checkFiles: false)
        let references = try StarterReferences(manifest: manifest, configuration: try .shipped())
        let dictionary = try PronouncingDictionary.bundled()
        return try manifest.phrases.map { phrase in
            let recording = try #require(phrase.recordings.first { $0.speaker == defaultVoice }, "\(phrase.id)")
            let input = try #require(references.phraseInput(phrase.id), "\(phrase.id)")
            return (phrase, starterFolder.appending(path: recording.audio),
                    SoundJudgeWords.expected(input.words, dictionary: dictionary))
        }
    }

    /// Checks the bar and that the judge really judged; prints the count and the words for the PR.
    static func check(_ judged: [(phrase: String, words: [JudgedWord])], source: String) {
        let flagged = judged.flatMap { phrase in
            phrase.words.filter(\.flagged).map { word in
                let phones = word.phones.filter(\.flagged)
                    .map { "\($0.phone)(\(String(format: "%.2f", $0.confidence)))" }.joined(separator: " ")
                return "\(phrase.phrase) #\(word.index.rawValue) \"\(word.text)\" \(phones)"
            }
        }
        let judgedWords = judged.flatMap(\.words).filter { if case .judged = $0.state { true } else { false } }.count
        let total = judged.flatMap(\.words).count
        print("starter regression (\(source)): \(flagged.count) flagged word(s) of \(judgedWords) judged / \(total)"
              + (flagged.isEmpty ? "" : ": " + flagged.joined(separator: "; ")))
        #expect(judged.count == 14, "every starter phrase")
        // A judge that judges nothing can't flag anything: the bar would pass vacuously.
        #expect(judgedWords * 10 >= total * 9, "\(judgedWords) of \(total) words judged")
        #expect(flagged.count <= flaggedWordBar, "FAIL: \(flagged.count) flagged: \(flagged)")
    }

    @Test("the 14 p311 starter references flag at most one word in total (committed posteriors)")
    func committedPosteriors() throws {
        var judged: [(phrase: String, words: [JudgedWord])] = []
        for (phrase, _, words) in try Self.starterPhrases() {
            let url = fixtureFolder.appending(path: "\(phrase.id).json")
            let fixture = try JSONDecoder().decode(StarterJudgeFixture.self, from: Data(contentsOf: url))
            #expect(fixture.phraseID == phrase.id.rawValue && fixture.recordingID.hasPrefix(defaultVoice))
            judged.append((phrase.id.rawValue, SoundScorer.judge(try fixture.posteriors, words: words)))
        }
        Self.check(judged, source: "fixtures")
    }

    @Test("the same with the real model (host only, AM_JUDGE_MODEL_DIR)",
          .enabled(if: ProcessInfo.processInfo.environment["AM_JUDGE_MODEL_DIR"] != nil),
          .timeLimit(.minutes(5)))
    func realModel() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AM_JUDGE_MODEL_DIR"]))
        let judge = try await SoundJudge.load(folder: folder)
        var judged: [(phrase: String, words: [JudgedWord])] = []
        for (phrase, audio, words) in try Self.starterPhrases() {
            let samples = try StarterReferences.decode16k(audio)
            judged.append((phrase.id.rawValue, try await judge.judge(samples: samples, words: words).words))
        }
        Self.check(judged, source: "model at \(folder.lastPathComponent)")
    }
}
