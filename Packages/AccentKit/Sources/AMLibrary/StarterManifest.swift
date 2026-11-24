// The bundled starter library's manifest (spec 15): `Resources/Starter/manifest.json`. Packs in order, each phrase's
// text, targets and pronunciation overrides, and its native recordings with full attribution. Packs, their order and
// their phrases come from this file only; nothing about them is written in Swift.

import AMCore
import Foundation

public struct StarterManifest: Sendable, Hashable, Codable {
    public static let fileName = "manifest.json"
    public static let currentFormatVersion = 1

    /// One sidebar pack. A pack with no phrases is shown as coming soon.
    public struct Pack: Sendable, Hashable, Codable {
        public let id: String
        public let title: String
        /// Phrase IDs, in the order the sidebar lists them.
        public let phrases: [PhraseID]

        public init(id: String, title: String, phrases: [PhraseID]) {
            self.id = id
            self.title = title
            self.phrases = phrases
        }
    }

    /// One native recording of a phrase: where it came from, its licence and its bundled files.
    public struct Recording: Sendable, Hashable, Codable {
        public let id: RecordingID
        /// The VCTK speaker, for example `p225`.
        public let speaker: String
        /// Copied from `fixtures/vctk/eval-speakers.json` (`bundled[]`), never typed by hand.
        public let accent: String
        public let region: String
        public let gender: String
        public let corpus: String
        public let licence: String
        public let sourceURL: String
        /// The corpus utterance, for example `p225_012`.
        public let utteranceID: String
        /// The clip in the corpus archive the bundled audio was cut from.
        public let sourceFile: String
        /// The cut, in seconds of the source clip.
        public let trimStart: Double
        public let trimEnd: Double
        /// Bundle-relative paths and their SHA-256s.
        public let audio: String
        public let audioSHA256: String
        /// The recorded WhisperKit word timings, shifted by `trimStart` (no ASR on the reference).
        public let timings: String
        public let timingsSHA256: String
        /// The L0/L1 analysis bytes (`AMPipeline`'s encoding) and the key they were computed for.
        public let analysis: String
        public let analysisSHA256: String
        public let analysisKey: String

        public init(
            id: RecordingID, speaker: String, accent: String, region: String, gender: String, corpus: String,
            licence: String, sourceURL: String, utteranceID: String, sourceFile: String, trimStart: Double,
            trimEnd: Double, audio: String, audioSHA256: String, timings: String, timingsSHA256: String,
            analysis: String, analysisSHA256: String, analysisKey: String
        ) {
            self.id = id
            self.speaker = speaker
            self.accent = accent
            self.region = region
            self.gender = gender
            self.corpus = corpus
            self.licence = licence
            self.sourceURL = sourceURL
            self.utteranceID = utteranceID
            self.sourceFile = sourceFile
            self.trimStart = trimStart
            self.trimEnd = trimEnd
            self.audio = audio
            self.audioSHA256 = audioSHA256
            self.timings = timings
            self.timingsSHA256 = timingsSHA256
            self.analysis = analysis
            self.analysisSHA256 = analysisSHA256
            self.analysisKey = analysisKey
        }
    }

    public struct Phrase: Sendable, Hashable, Codable {
        public let id: PhraseID
        public let text: String
        /// 0-based word indices after spec 06's tokenisation (bare punctuation skipped).
        public let targets: [Int]
        /// ARPAbet overrides keyed by word index.
        public let pronunciations: [Int: String]
        /// The default selected voice (the headline reference).
        public let headlineVoice: RecordingID
        /// Headline voice first, then CPO's voice order.
        public let recordings: [Recording]

        public init(
            id: PhraseID, text: String, targets: [Int], pronunciations: [Int: String], headlineVoice: RecordingID,
            recordings: [Recording]
        ) {
            self.id = id
            self.text = text
            self.targets = targets
            self.pronunciations = pronunciations
            self.headlineVoice = headlineVoice
            self.recordings = recordings
        }

        public func recording(_ id: RecordingID) -> Recording? { recordings.first { $0.id == id } }

        /// SHA-256 of the sorted recording audio hashes, one per line: the band's `nativeSetHash`.
        public var nativeSetHash: String {
            SHA256Digest.hex(of: Data(recordings.map(\.audioSHA256).sorted().joined(separator: "\n").utf8))
        }

        /// `ReferenceIdentity` for `voice`: the recording, the phrase's overrides and targets, the native set.
        public func identity(voice: RecordingID) -> ReferenceIdentity {
            ReferenceIdentity(
                phraseID: id, recordingID: voice, recordingSHA256: recording(voice)?.audioSHA256 ?? "",
                transcriptRevision: 0,
                pronunciationOverridesHash: (try? CanonicalJSON.sha256(pronunciations)) ?? "",
                targetsHash: (try? CanonicalJSON.sha256(targets.sorted())) ?? "", nativeSetHash: nativeSetHash)
        }
    }

    public let formatVersion: Int
    /// The recogniser the bundled word timings were recorded with.
    public let asrModelID: String
    public let packs: [Pack]
    public let phrases: [Phrase]

    public init(formatVersion: Int = Self.currentFormatVersion, asrModelID: String, packs: [Pack], phrases: [Phrase]) {
        self.formatVersion = formatVersion
        self.asrModelID = asrModelID
        self.packs = packs
        self.phrases = phrases
    }

    public func phrase(_ id: PhraseID) -> Phrase? { phrases.first { $0.id == id } }

    /// What can be wrong with a manifest, each naming the item.
    public enum Problem: Error, Sendable, Hashable, CustomStringConvertible {
        case unsupportedFormatVersion(Int)
        case duplicatePack(String)
        case duplicatePhrase(PhraseID)
        case duplicateRecording(RecordingID)
        /// A pack lists a phrase the manifest doesn't define.
        case unknownPhrase(pack: String, phrase: PhraseID)
        /// A phrase no pack lists.
        case phraseInNoPack(PhraseID)
        case noTargets(PhraseID)
        case noRecordings(PhraseID)
        case unknownHeadlineVoice(phrase: PhraseID, voice: RecordingID)
        case missingFile(String)
        case shaMismatch(path: String, expected: String, actual: String)

        public var description: String {
            switch self {
            case .unsupportedFormatVersion(let v): "unsupported manifest formatVersion \(v)"
            case .duplicatePack(let id): "duplicate pack \(id)"
            case .duplicatePhrase(let id): "duplicate phrase \(id)"
            case .duplicateRecording(let id): "duplicate recording \(id)"
            case .unknownPhrase(let pack, let phrase): "pack \(pack) lists unknown phrase \(phrase)"
            case .phraseInNoPack(let id): "phrase \(id) is in no pack"
            case .noTargets(let id): "phrase \(id) has no target"
            case .noRecordings(let id): "phrase \(id) has no recording"
            case .unknownHeadlineVoice(let phrase, let voice): "phrase \(phrase): headline voice \(voice) isn't one of its recordings"
            case .missingFile(let path): "missing file \(path)"
            case .shaMismatch(let path, let expected, let actual): "\(path): SHA-256 \(actual), manifest says \(expected)"
            }
        }
    }

    /// Every structural problem (no file access); empty when the manifest is sound.
    public func problems() -> [Problem] {
        var problems: [Problem] = []
        if formatVersion != Self.currentFormatVersion { problems.append(.unsupportedFormatVersion(formatVersion)) }
        var packIDs: Set<String> = []
        for pack in packs where !packIDs.insert(pack.id).inserted { problems.append(.duplicatePack(pack.id)) }
        var phraseIDs: Set<PhraseID> = []
        var recordingIDs: Set<RecordingID> = []
        for phrase in phrases {
            if !phraseIDs.insert(phrase.id).inserted { problems.append(.duplicatePhrase(phrase.id)) }
            if phrase.targets.isEmpty { problems.append(.noTargets(phrase.id)) }
            if phrase.recordings.isEmpty { problems.append(.noRecordings(phrase.id)) }
            if phrase.recording(phrase.headlineVoice) == nil {
                problems.append(.unknownHeadlineVoice(phrase: phrase.id, voice: phrase.headlineVoice))
            }
            for recording in phrase.recordings where !recordingIDs.insert(recording.id).inserted {
                problems.append(.duplicateRecording(recording.id))
            }
        }
        let listed = Set(packs.flatMap(\.phrases))
        for pack in packs {
            for phrase in pack.phrases where !phraseIDs.contains(phrase) {
                problems.append(.unknownPhrase(pack: pack.id, phrase: phrase))
            }
        }
        for phrase in phrases where !listed.contains(phrase.id) { problems.append(.phraseInNoPack(phrase.id)) }
        return problems
    }

    /// Every file the manifest names that is missing from `folder` or doesn't match its SHA-256.
    public func fileProblems(in folder: URL) -> [Problem] {
        var problems: [Problem] = []
        for recording in phrases.flatMap(\.recordings) {
            for (path, expected) in [
                (recording.audio, recording.audioSHA256), (recording.timings, recording.timingsSHA256),
                (recording.analysis, recording.analysisSHA256),
            ] {
                guard let data = try? Data(contentsOf: folder.appending(path: path)) else {
                    problems.append(.missingFile(path))
                    continue
                }
                let actual = SHA256Digest.hex(of: data)
                if actual != expected { problems.append(.shaMismatch(path: path, expected: expected, actual: actual)) }
            }
        }
        return problems
    }

    /// Decodes `folder/manifest.json` and validates it, files included. Throws the first problem found.
    public static func load(from folder: URL, checkFiles: Bool = true) throws -> StarterManifest {
        let manifest = try JSONDecoder().decode(
            StarterManifest.self, from: Data(contentsOf: folder.appending(path: fileName)))
        if let problem = manifest.problems().first { throw problem }
        if checkFiles, let problem = manifest.fileProblems(in: folder).first { throw problem }
        return manifest
    }

    /// The manifest as the builder writes it: sorted keys, pretty-printed, so two builds are byte-identical.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}
