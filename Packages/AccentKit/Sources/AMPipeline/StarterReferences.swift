// The bundled starter library, as the pipeline reads it (spec 15): each manifest phrase as a `PhraseInput` (CPO's
// overrides, spec 06's selector), and the rebuilder `ReferenceLibrary` calls when a bundled analysis is stale or a
// cached one corrupt. A native recording is analysed from its bundled audio (decoded, resampled to 16 kHz) and its
// bundled word timings (replayed: no ASR on the reference). `scripts/build-starter.sh` builds the bundle with the same
// code, so the CI check can recompute every bundled analysis and compare.

import Accelerate
import AMAlignment
import AMCore
import AMLibrary
@preconcurrency import AVFAudio
import Foundation

public struct StarterReferences: Sendable {
    public enum Failure: Error, Sendable, Hashable, CustomStringConvertible {
        case unknownPhrase(PhraseID)
        case invalidPhrase(PhraseID, [StarterPhraseProblem])
        case unreadableAudio(String)
        case unsupportedSampleRate(Double)
        case timingsModelMismatch(String)

        public var description: String {
            switch self {
            case .unknownPhrase(let id): "unknown phrase \(id)"
            case .invalidPhrase(let id, let problems): "phrase \(id) fails the starter validator: \(problems)"
            case .unreadableAudio(let path): "cannot read audio \(path)"
            case .unsupportedSampleRate(let rate): "unsupported sample rate \(rate) (needs an integer multiple of 16 kHz)"
            case .timingsModelMismatch(let path): "\(path): timings recorded with another model than the manifest's"
            }
        }
    }

    public let configuration: Analyzer.Configuration
    private let inputs: [PhraseID: PhraseInput]

    /// Builds every phrase's input; throws if a phrase fails spec 06's starter validator.
    public init(manifest: StarterManifest, configuration: Analyzer.Configuration) throws {
        let selector = try PronunciationSelector.bundled()
        let dictionary = try PronouncingDictionary.bundled()
        var inputs: [PhraseID: PhraseInput] = [:]
        for phrase in manifest.phrases {
            inputs[phrase.id] = try Self.input(phrase, selector: selector, dictionary: dictionary)
        }
        self.configuration = configuration
        self.inputs = inputs
    }

    /// The phrase as the analyzer reads it.
    public func phraseInput(_ id: PhraseID) -> PhraseInput? { inputs[id] }

    /// What `ReferenceLibrary` injects: the running code's key for a recording, and its rebuild.
    public var rebuilder: ReferenceRebuilder {
        let references = self
        return ReferenceRebuilder(
            expectedKey: { references.expectedKey($0) },
            rebuild: { try await references.analyse($0) })
    }

    /// The L1 key `analyse` gives `source`'s analysis under this configuration.
    public func expectedKey(_ source: StarterRecordingSource) -> String {
        guard let input = inputs[source.phrase.id] else { return "" }
        let l0 = L0Key(
            takeAudioSHA256: source.recording.audioSHA256, asrModelID: source.asrModelID,
            pitchTrackerID: configuration.pitchTracker.id, voicingID: configuration.voicing.id)
        return L1Key(
            l0: l0, transcriptRevision: input.transcriptRevision, pronunciationHash: input.pronunciationHash,
            aligner: configuration.boundaryRefiner.id
        ).text
    }

    /// `source`'s L0/L1 analysis from its bundled audio and replayed word timings.
    public func analyse(_ source: StarterRecordingSource) async throws -> DerivedRecord {
        guard let input = inputs[source.phrase.id] else { throw Failure.unknownPhrase(source.phrase.id) }
        let timings = try JSONDecoder().decode(RecordedTimestamps.self, from: Data(contentsOf: source.timings))
        guard timings.asrModelID == source.asrModelID else { throw Failure.timingsModelMismatch(source.timings.lastPathComponent) }
        let take = TakeAudio(
            samples: try Self.decode16k(source.audio), sha256: source.recording.audioSHA256,
            clipID: source.recording.id.rawValue, recordedAt: Date(timeIntervalSince1970: 0))
        let analyzer = Analyzer(
            speech: SpeechModelHost(ready: ReplayedWords(asrModelID: timings.asrModelID, words: timings.words)),
            configuration: configuration)
        return try await analyzer.analyseNative(take: take, phrase: input)
    }

    // MARK: - Phrases

    /// A starter phrase's words: CPO's overrides first, then spec 06's selector (no tagger for starters). A(w) is the
    /// selected pattern's primary syllable for words of two or more syllables.
    public static func input(
        _ phrase: StarterManifest.Phrase, selector: PronunciationSelector, dictionary: PronouncingDictionary
    ) throws -> PhraseInput {
        let file = PhrasePronunciationFile(text: phrase.text, targets: phrase.targets, pronunciations: phrase.pronunciations)
        let problems = StarterPhraseValidator.problems(in: file, dictionary: dictionary)
        guard problems.isEmpty else { throw Failure.invalidPhrase(phrase.id, problems) }
        let words = try selector.expectedPhrase(for: try file.phraseText()).words.map { word in
            let pronunciation = try word.pronunciation ?? Pronunciation(arpabet: fallbackPhones(word.text, dictionary: dictionary))
            let pattern = word.expectedPattern ?? []
            let accepted = pattern.count >= 2 ? pattern.firstIndex(of: .primary).map { Set([$0]) } : nil
            return PlacementTake.Word(index: word.index, text: word.text, pronunciation: pronunciation, accepted: accepted)
        }
        return PhraseInput(id: phrase.id, words: words)
    }

    /// CMUdict's first variant, else one schwa per spelling syllable (an out-of-vocabulary word still needs a
    /// syllable count). The same fallback as the agreement harness.
    static func fallbackPhones(_ text: String, dictionary: PronouncingDictionary) -> String {
        let folded = WordText.fold(text)
        if let first = dictionary.pronunciations(of: folded).first { return first.arpabet }
        let count = max(Syllabifier.spellingSyllables(of: folded).count, 1)
        return Array(repeating: "AH0", count: count).joined(separator: " ")
    }

    // MARK: - Audio

    /// The file's first channel at 16 kHz mono Float32. FLAC is decoded losslessly; the rate is brought down by
    /// `resample`, so the result is the same on every Mac.
    public static func decode16k(_ url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw Failure.unreadableAudio(url.lastPathComponent)
        }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0]
        else { throw Failure.unreadableAudio(url.lastPathComponent) }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return try resample(samples, from: format.sampleRate, to: TakeAudio.sampleRate)
    }

    /// Downsamples by an integer factor with a Blackman-windowed sinc low-pass at 0.45 × the target rate, through
    /// vDSP: the agreement harness's filter (`AMEvaluation.AudioFiles.resample`), which the app can't link.
    public static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        if sourceRate == targetRate { return samples }
        let ratio = sourceRate / targetRate
        guard ratio > 1, ratio == ratio.rounded() else { throw Failure.unsupportedSampleRate(sourceRate) }
        let factor = Int(ratio)
        let taps = 32 * factor + 1
        let cutoff = 0.45 / ratio
        let centre = Double(taps - 1) / 2
        var filter = (0..<taps).map { i -> Float in
            let x = Double(i) - centre
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            let window = 0.42 - 0.5 * cos(2 * .pi * Double(i) / Double(taps - 1))
                + 0.08 * cos(4 * .pi * Double(i) / Double(taps - 1))
            return Float(sinc * window)
        }
        let gain = filter.reduce(0, +)
        filter = filter.map { $0 / gain }
        let pad = [Float](repeating: 0, count: taps / 2)
        let padded = pad + samples + pad + [Float](repeating: 0, count: factor)
        let outputCount = samples.count / factor
        var output = [Float](repeating: 0, count: outputCount)
        vDSP_desamp(padded, vDSP_Stride(factor), filter, &output, vDSP_Length(outputCount), vDSP_Length(taps))
        return output
    }
}

/// One recording's recorded word timings, replayed whatever the request.
struct ReplayedWords: WordTimestamper {
    let asrModelID: String
    let words: [WordTimestamp]

    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        try Task.checkCancellation()
        return words
    }
}

extension ReferenceLibrary {
    /// The bundled library with the pipeline's rebuilder: what the app (spec 21) opens.
    public static func bundled(
        folder: URL, caches: URL, configuration: Analyzer.Configuration
    ) throws -> (library: ReferenceLibrary, references: StarterReferences) {
        let manifest = try StarterManifest.load(from: folder)
        let references = try StarterReferences(manifest: manifest, configuration: configuration)
        let library = try ReferenceLibrary(
            bundle: folder, caches: caches, rebuilder: references.rebuilder, manifest: manifest)
        return (library, references)
    }
}
