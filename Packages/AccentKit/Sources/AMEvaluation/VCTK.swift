// The VCTK positive set (plan §6.1, §6.2): the eval-speaker manifest, the tuning-only selection API, the pair
// builder and the VCTK CV folds.

import Foundation
import AMCore

public enum VCTK {
    /// CPO's 20 starter phrases.
    public static let starterPhrases = [
        "002", "003", "004", "005", "006", "007", "008", "009", "010", "011",
        "012", "013", "014", "015", "016", "017", "018", "019", "020", "024",
    ]
    /// The shared-text prompts CPO's 20 left out (CTO ruling on the positive-set shortfall). The picker lists a
    /// speaker's clip of one only if its transcript is the shared text (`phraseText` in eval-speakers.json).
    public static let addedPhrases = ["001", "021", "022", "023"]
    /// Every positive-set phrase: VCTK 0.92's shared-text prompts 001–024.
    public static let phrases = (starterPhrases + addedPhrases).sorted()
    /// The bundled reference voices (mic1).
    public static let bundledVoices = ["p225", "p226", "p227", "p233", "p241", "p252", "p311", "p345"]
    /// Never used: p280 and p315.
    public static let excludedSpeakers = ["p280", "p315"]

    /// The shared prompt a phrase comes from: itself, or `021` for the sub-phrase `021-a` (spec 24).
    public static func sourcePrompt(of phrase: String) -> String {
        String(phrase.prefix { $0 != "-" })
    }

    /// The headline reference of a phrase: p225, or p226 for 015 (p225 has no 015).
    public static func headlineReference(for phrase: String) -> String {
        sourcePrompt(of: phrase) == "015" ? "p226" : "p225"
    }

    /// The native readers of a phrase: the bundled voices that have it. The only voices that may build a band or
    /// add to A(w). Held-out speakers can't appear here: the list is fixed.
    public static func nativeReaders(for phrase: String) -> [String] {
        bundledVoices.filter { !($0 == "p225" && sourcePrompt(of: phrase) == "015") }
    }
}

public enum VCTKSplit: String, Sendable, Hashable, Codable {
    case tuning
    case heldOut
}

/// `fixtures/vctk/eval-speakers.json`, written by `tools/pick_vctk_eval_speakers.py`.
public struct VCTKEvalSpeakersManifest: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable {
        public let speaker: String
        public let accent: String
        public let gender: String
        /// nil for the bundled voices.
        public let split: VCTKSplit?
        /// Phrase id → SHA-256 of the official `{speaker}_{phrase}_mic1.flac`.
        public let files: [String: String]
    }

    public let corpus: String
    public let seed: UInt64
    public let phrases: [String]
    /// Prompt id → the normalised shared text a listed clip's transcript must read (the prompts the CTO ruling added).
    public let phraseText: [String: String]?
    public let bundled: [Entry]
    public let speakers: [Entry]
    /// The recorded split sizes (24 / 16 after the CTO ruling). Floors, not exact counts: `meetsFloors`.
    public let tuningCount: Int
    public let heldOutCount: Int

    /// Speaker floors (spec 02, CTO ruling 2026-11-23 14:18): at least 18 tuning and at least
    /// `agreement.positiveHeldOutSpeakers` (12) held-out. Not a tunable: the plan's split floor.
    public static let minimumTuningSpeakers = 18
    public static func minimumHeldOutSpeakers(thresholds: Thresholds = .current) -> Int {
        Int(thresholds.agreement.positiveHeldOutSpeakers)
    }

    /// The recorded counts match the listed speakers and meet the floors.
    public func meetsFloors(thresholds: Thresholds = .current) -> Bool {
        tuningCount == tuningSpeakers.count && heldOutCount == heldOutSpeakers.count
            && tuningCount >= Self.minimumTuningSpeakers
            && heldOutCount >= Self.minimumHeldOutSpeakers(thresholds: thresholds)
    }

    public static func load(_ url: URL) throws -> VCTKEvalSpeakersManifest {
        try JSONDecoder().decode(VCTKEvalSpeakersManifest.self, from: Data(contentsOf: url))
    }

    /// The tuning speakers (at least 18). The only way to get a `TuningSpeaker`.
    public var tuningSpeakers: [TuningSpeaker] {
        speakers.filter { $0.split == .tuning }.map { TuningSpeaker(id: $0.speaker, accent: $0.accent, gender: $0.gender) }
    }

    /// The held-out speakers (at least 12), for the pair builder only.
    public var heldOutSpeakers: [HeldOutSpeaker] {
        speakers.filter { $0.split == .heldOut }.map { HeldOutSpeaker(id: $0.speaker) }
    }

    /// SHA-256 of the sorted file hashes of every source file the manifest names (the corpus manifest hash).
    public var corpusManifestHash: String {
        ReportHashes.corpusManifestHash(fileHashes: (bundled + speakers).flatMap { $0.files.values })
    }
}

/// A VCTK tuning speaker. Only `VCTKEvalSpeakersManifest.tuningSpeakers` can make one, so an API that takes
/// `[TuningSpeaker]` (spec 22's voice selection, every inner tuning step) cannot receive a held-out VCTK speaker or a
/// speechocean762 word: the rule is enforced by type, not by convention. Deliberately not `Decodable`, so no file can
/// mint one either.
public struct TuningSpeaker: Sendable, Hashable {
    public let id: String
    public let accent: String
    public let gender: String

    fileprivate init(id: String, accent: String, gender: String) {
        self.id = id
        self.accent = accent
        self.gender = gender
    }
}

/// A held-out VCTK speaker: evaluated against the bundled references, never a reference, a band voice or in A(w).
public struct HeldOutSpeaker: Sendable, Hashable {
    public let id: String

    fileprivate init(id: String) { self.id = id }
}

/// Selection that may only look at tuning speakers (spec 22's TTS voice choice, inner tuning steps).
public enum TuningOnlySelection {
    /// Picks the speaker with the best score; ties go to the lower id. The signature is the guard: only
    /// `TuningSpeaker`s go in.
    public static func best(
        of speakers: [TuningSpeaker], score: (TuningSpeaker) throws -> Double
    ) rethrows -> TuningSpeaker? {
        var best: (TuningSpeaker, Double)?
        for speaker in speakers.sorted(by: { $0.id < $1.id }) {
            let value = try score(speaker)
            if best == nil || value > best!.1 { best = (speaker, value) }
        }
        return best?.0
    }
}

/// One scored VCTK pair: an eval speaker's take of a phrase against a bundled reference.
public struct VCTKPair: Sendable, Hashable, Codable {
    public let speaker: String
    public let phrase: String
    public let reference: String

    public init(speaker: String, phrase: String, reference: String) {
        self.speaker = speaker
        self.phrase = phrase
        self.reference = reference
    }

    /// The shared prompt the pair's phrase comes from.
    public var sourcePrompt: String { VCTK.sourcePrompt(of: phrase) }

    /// The pair as a scored unit: its phrase for the worst-phrase figure, clustered under its source prompt for the
    /// two-way bootstrap (sub-phrases of one prompt share a reader, a session and context, spec 24).
    public func scoredUnit(hit: Bool) -> ScoredUnit {
        ScoredUnit(speaker: speaker, phrase: phrase, phraseCluster: sourcePrompt, hit: hit)
    }
}

/// A clip that survived the trim (2–6 s).
public struct VCTKClip: Sendable, Hashable, Codable {
    public let speaker: String
    public let phrase: String

    public init(speaker: String, phrase: String) {
        self.speaker = speaker
        self.phrase = phrase
    }
}

/// The headline (held-out × phrase against the phrase's bundled reference) and secondary (against every bundled
/// voice, correlated) pairs, and whether the headline set is big enough to evaluate.
public struct VCTKPairs: Sendable, Hashable {
    public let headline: [VCTKPair]
    public let secondary: [VCTKPair]

    /// `phrases`: the positive set's phrases (`VCTKSubPhraseTable.evaluationPhrases`, or `VCTK.phrases` unsplit).
    public init(manifest: VCTKEvalSpeakersManifest, available: Set<VCTKClip>, phrases: [String]) {
        var headline: [VCTKPair] = []
        var secondary: [VCTKPair] = []
        for speaker in manifest.heldOutSpeakers.map(\.id).sorted() {
            for phrase in phrases where available.contains(VCTKClip(speaker: speaker, phrase: phrase)) {
                let reference = VCTK.headlineReference(for: phrase)
                if available.contains(VCTKClip(speaker: reference, phrase: phrase)) {
                    headline.append(VCTKPair(speaker: speaker, phrase: phrase, reference: reference))
                }
                for voice in VCTK.nativeReaders(for: phrase)
                where available.contains(VCTKClip(speaker: voice, phrase: phrase)) {
                    secondary.append(VCTKPair(speaker: speaker, phrase: phrase, reference: voice))
                }
            }
        }
        self.headline = headline
        self.secondary = secondary
    }

    /// Phrases with a headline pair: whole prompts plus sub-phrases (spec 24).
    public var phraseCount: Int { Set(headline.map(\.phrase)).count }
    /// The distinct shared prompts behind those phrases. Sub-phrases of one prompt are correlated, so this is printed
    /// next to the phrase count every time.
    public var sourcePromptCount: Int { Set(headline.map(\.sourcePrompt)).count }
    public var heldOutSpeakerCount: Int { Set(headline.map(\.speaker)).count }

    /// One §6.2 minimum: what it counts, the measured value and the floor.
    public struct Minimum: Sendable, Hashable {
        public let name: String
        public let value: Int
        public let minimum: Int
        public var isMet: Bool { value >= minimum }

        /// PASS when met, otherwise NOT EVALUATED: a short positive set is never a FAIL and never a pass.
        public var line: String { "\(name) \(value) (≥ \(minimum)): \(isMet ? "PASS" : "NOT EVALUATED")" }
    }

    /// The §6.2 minimums. The phrase minimum is checked on the phrase count (CTO ruling, spec 24 Open question 2).
    public func minimums(thresholds: Thresholds = .current) -> [Minimum] {
        [
            Minimum(name: "pairs", value: headline.count, minimum: Int(thresholds.agreement.positiveMinPairs)),
            Minimum(name: "phrases", value: phraseCount, minimum: Self.minimumPhrases),
            Minimum(
                name: "held-out speakers", value: heldOutSpeakerCount,
                minimum: Int(thresholds.agreement.positiveHeldOutSpeakers)),
        ]
    }

    /// The §6.2 minimums (pairs, phrases after trimming, held-out speakers). Empty when the headline set can be
    /// evaluated; otherwise each shortfall, and every positive-set metric is NOT EVALUATED.
    public func shortfalls(thresholds: Thresholds = .current) -> [String] {
        minimums(thresholds: thresholds).filter { !$0.isMet }.map { m in
            "\(m.name) \(m.value) < \(m.minimum)"
                + (m.name == "phrases" ? " (\(sourcePromptCount) distinct source prompts)" : "")
        }
    }

    /// "≥ 18 phrases after trimming" (§6.2). Not a tunable: it is the plan's evaluability floor, and the CTO ruling
    /// keeps it at 18 with the widened phrase set.
    public static let minimumPhrases = 18

    /// Per phrase, how many clips the trim rejected (all speakers) and whether the headline reference survived. A
    /// sub-phrase always gets a line, with its MFA-mismatch rejections next to the trim's (spec 24).
    public static func rejectionsByPhrase(
        trimmed: [VCTKClip], misaligned: [VCTKClip] = [], phrases: [String], manifest: VCTKEvalSpeakersManifest
    ) -> [String] {
        let heldOut = Set(manifest.heldOutSpeakers.map(\.id))
        func count(_ clips: [VCTKClip], _ by: String) -> String {
            "\(clips.count) \(by) (\(clips.filter { heldOut.contains($0.speaker) }.count) held-out)"
        }
        return phrases.compactMap { phrase in
            let trim = trimmed.filter { $0.phrase == phrase }
            let mfa = misaligned.filter { $0.phrase == phrase }
            let isSubPhrase = VCTK.sourcePrompt(of: phrase) != phrase
            guard isSubPhrase || !trim.isEmpty || !mfa.isEmpty else { return nil }
            let reference = VCTK.headlineReference(for: phrase)
            let referenceLost = (trim + mfa).contains { $0.speaker == reference }
            let counts = isSubPhrase
                ? count(trim, "rejected by the trim") + ", " + count(mfa, "by MFA mismatch")
                : count(trim, "rejected")
            return "\(phrase): " + counts + (referenceLost ? ", reference \(reference) rejected: phrase dropped" : "")
        }
    }
}

/// The VCTK CV estimate's folds: 6 speaker-disjoint outer folds over the tuning speakers (≥ 18), stratified by gender.
public enum VCTKFolds {
    public static func make(_ speakers: [TuningSpeaker], count: Int = 6, seed: UInt64) -> [OuterFold] {
        FoldAssignment.stratified(speakers: speakers.map { ($0.id, $0.gender) }, count: count, seed: seed)
            .enumerated().map { OuterFold(index: $0, speakers: $1) }
    }
}
