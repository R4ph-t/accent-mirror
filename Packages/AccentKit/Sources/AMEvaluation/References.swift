// Spec 11 §3a (CTO, 2026-11-24 12:53): the positive set's native references. No single headline reference: each
// phrase has an ordered list of at least 3 native speakers, fixed in a committed manifest before any scoring
// (`fixtures/vctk/reference-lists.json`), built from clip availability only, never from results. The bundled voices
// come first in their order (p226 first for 015), then tuning speakers only if fewer than 3 bundled voices have a
// take. A held-out speaker is never a reference and a speaker is never their own reference.

import AMCore
import Foundation

/// The committed reference lists.
public struct VCTKReferenceLists: Sendable, Hashable, Codable {
    public static let minimumReferences = 3

    public let version: Int
    public let rule: String
    /// SHA-256 of the eval-speakers manifest the lists were built from.
    public let evalSpeakersSHA256: String
    /// Phrase → ordered reference speakers.
    public let phrases: [String: [String]]

    public init(version: Int = 1, rule: String, evalSpeakersSHA256: String, phrases: [String: [String]]) {
        self.version = version
        self.rule = rule
        self.evalSpeakersSHA256 = evalSpeakersSHA256
        self.phrases = phrases
    }

    public static let ruleText = "bundled voices in order (p225, p226, p227, p233, p241, p252, p311, p345; p226 first "
        + "and p225 left out for 015), each only with a kept clip of the phrase; then tuning speakers in id order, "
        + "only while fewer than 3 references have a kept clip; never a held-out speaker"

    /// Builds the lists from the trimmed cache's kept clips (availability only).
    public static func make(
        manifest: VCTKEvalSpeakersManifest, available: Set<VCTKClip>, phrases: [String], evalSpeakersSHA256: String
    ) -> VCTKReferenceLists {
        var out: [String: [String]] = [:]
        let tuning = manifest.tuningSpeakers.map(\.id).sorted()
        for phrase in phrases {
            var order = VCTK.nativeReaders(for: phrase)
            if VCTK.sourcePrompt(of: phrase) == "015" { order = ["p226"] + order.filter { $0 != "p226" } }
            var list = order.filter { available.contains(VCTKClip(speaker: $0, phrase: phrase)) }
            for speaker in tuning where list.count < minimumReferences
                && available.contains(VCTKClip(speaker: speaker, phrase: phrase))
            {
                list.append(speaker)
            }
            out[phrase] = list
        }
        return VCTKReferenceLists(rule: ruleText, evalSpeakersSHA256: evalSpeakersSHA256, phrases: out)
    }

    public static func load(_ url: URL) throws -> VCTKReferenceLists {
        try JSONDecoder().decode(VCTKReferenceLists.self, from: Data(contentsOf: url))
    }

    /// The references a take by `speaker` may use for `phrase`, in order (never the speaker themself).
    public func references(for phrase: String, speaker: String) -> [String] {
        (phrases[phrase] ?? []).filter { $0 != speaker }
    }

    /// Fatal problems: a held-out speaker in a list.
    public func problems(manifest: VCTKEvalSpeakersManifest) -> [String] {
        let heldOut = Set(manifest.heldOutSpeakers.map(\.id))
        return phrases.sorted(by: { $0.key < $1.key }).compactMap { phrase, list in
            heldOut.isDisjoint(with: list) ? nil : "\(phrase): a held-out speaker is a reference"
        }
    }

    /// Lists shorter than the minimum because too few non-held-out speakers have a kept clip (reported, not fixed:
    /// the trim rule and the split don't move).
    public var shortLists: [String] {
        phrases.sorted(by: { $0.key < $1.key }).compactMap { phrase, list in
            list.count >= Self.minimumReferences ? nil
                : "\(phrase): \(list.count) references (< \(Self.minimumReferences)): only \(list.count) non-held-out speakers have a kept 2–6 s take"
        }
    }
}

/// Why a word (of a reference take, or of a held-out take) can't be used (§3a's transcript check).
public enum WordUsabilityProblem: String, Sendable, Hashable, Codable, CaseIterable {
    /// Whisper heard another word there.
    case asrSubstitution
    /// Whisper heard nothing for the word.
    case asrMissing
    /// The word's Whisper probability is below `confidence.levelMedium`.
    case lowAsrConfidence
    /// Spec 07's span sanity check failed.
    case spanSanityFailed
    /// The clip is outside 2–6 s and was never kept.
    case trimRejected
    /// Every reference in the list failed.
    case noUsableReference
}

/// One positive-set pair's accounting: which reference served it (every word, here) or why it was lost.
public struct PairAccount: Sendable, Hashable, Codable {
    public let speaker: String
    public let phrase: String
    /// The reference that served every word of the pair; nil when the pair was lost.
    public let reference: String?
    /// References tried before it, each with its first problem word's reason.
    public let skipped: [String: WordUsabilityProblem]
    /// Why the pair was lost (nil when scored).
    public let lostReason: String?

    public init(speaker: String, phrase: String, reference: String?, skipped: [String: WordUsabilityProblem], lostReason: String?) {
        self.speaker = speaker
        self.phrase = phrase
        self.reference = reference
        self.skipped = skipped
        self.lostReason = lostReason
    }
}

/// §3a's per-row accounting printed next to every positive row.
public struct RowAccounting: Sendable, Hashable, Codable {
    /// Pairs the row measured.
    public let pairs: Int
    public let referenceSpeakers: Int
    public let prompts: Int
    /// Pairs of the set the row didn't measure.
    public let lostPairs: Int
    public let lostReasons: [String: Int]

    public init(pairs: Int, referenceSpeakers: Int, prompts: Int, lostPairs: Int, lostReasons: [String: Int]) {
        self.pairs = pairs
        self.referenceSpeakers = referenceSpeakers
        self.prompts = prompts
        self.lostPairs = lostPairs
        self.lostReasons = lostReasons
    }

    /// The row's accounting: `measured` are the pairs the row counted (speaker_phrase ids), `why` names why a scored
    /// pair didn't count in the row.
    public static func make(
        accounts: [PairAccount], measured: Set<String>, why: (String) -> String
    ) -> RowAccounting {
        var reasons: [String: Int] = [:]
        var refs: Set<String> = []
        var prompts: Set<String> = []
        for a in accounts {
            let id = "\(a.speaker)_\(a.phrase)"
            if measured.contains(id) {
                if let r = a.reference { refs.insert(r) }
                prompts.insert(VCTK.sourcePrompt(of: a.phrase))
            } else {
                reasons[a.lostReason ?? why(id), default: 0] += 1
            }
        }
        return RowAccounting(
            pairs: measured.count, referenceSpeakers: refs.count, prompts: prompts.count,
            lostPairs: accounts.count - measured.count, lostReasons: reasons)
    }

    public var text: String {
        "pairs \(pairs), reference speakers \(referenceSpeakers), prompts \(prompts), lost \(lostPairs)"
            + (lostReasons.isEmpty ? "" : " (" + lostReasons.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "; ") + ")")
    }
}
