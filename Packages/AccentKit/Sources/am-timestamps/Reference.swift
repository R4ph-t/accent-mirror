import AMTimestampEval
import Foundation

// The reference sanity check (CTO review of spec 23). `reference-phrases` lists each eval phrase once (one per text
// ID, its transcript from the first speaker that has it); spec 22's TTS tool under tools/ (TTS never lives in
// AccentKit; scripts/reference-check.sh runs it) synthesises them with a pinned on-device voice, with an SSML <mark> before and after
// every word, and writes an MFA input corpus (WAV + .lab) and the marker spans; `reference-compare` compares MFA's
// alignment of that audio with the markers. Local tooling: no network, no audio in git.

/// One phrase for the TTS tool to speak.
struct ReferencePhrase: Codable {
    var clipID: String
    var transcript: String
}

/// The marker spans of one synthesised phrase.
struct MarkedPhrase: Codable {
    var clipID: String
    var transcript: String
    var words: [BaselineWord]
    var wordsWithoutMarkers: Int
}

/// What the TTS tool writes next to the corpus (its own `MarkerFile` has the same JSON shape).
struct MarkerFile: Codable {
    var voice: String
    var sampleRate: Double
    var bufferFrames: Int
    var phrases: [MarkedPhrase]
}

extension AMTimestamps {
    // MARK: - reference-phrases

    static func referencePhrases(_ options: Options) throws -> Int32 {
        var seen: Set<String> = []
        var phrases: [ReferencePhrase] = []
        for clip in try clips(options).present {
            let textID = String(clip.id.split(separator: "_")[1])
            guard seen.insert(textID).inserted else { continue }
            phrases.append(ReferencePhrase(clipID: "tts_\(textID)", transcript: try clip.text()))
        }
        let out = try options.url("out")
        try writeJSON(phrases, to: out)
        print("reference-phrases: \(phrases.count) phrases → \(out.path)")
        return 0
    }

    // MARK: - reference-compare

    static func referenceCompare(_ options: Options) throws -> Int32 {
        let markers = try JSONDecoder().decode(MarkerFile.self, from: Data(contentsOf: try options.url("markers")))
        let baseline = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: try options.url("baseline")))
        let aligned = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })
        let check = ReferenceCheck.compare(
            markers.phrases.map {
                ReferenceCheck.Clip(clipID: $0.clipID, transcript: $0.transcript, markers: $0.words,
                                    aligned: aligned[$0.clipID] ?? [])
            },
            voice: markers.voice,
            aligner: "\(baseline.aligner.name) \(baseline.aligner.version) (\(baseline.aligner.acousticModel))",
            markerResolutionMs: markers.sampleRate > 0 ? Double(markers.bufferFrames) / markers.sampleRate * 1000 : 0,
            wordsWithoutMarkers: markers.phrases.map(\.wordsWithoutMarkers).reduce(0, +))
        try writeJSON(check, to: try options.url("out"))
        print("reference-compare: \(check.line)")
        return 0
    }
}
