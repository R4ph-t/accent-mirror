import AMAlignment
import AMCore
import Foundation

// Report identity (plan §6.6). `ConfigIdentity`, `CanonicalJSON` and `configDigest` are spec 01's, in AMCore; this
// file adds only what the timestamp report needs on top: the canonical JSON kept for recomputing by hand, the source
// tree hash and the corpus hash.

extension ConfigIdentity {
    /// Spec 03's identity: AMCore's current versions, the pinned ASR model, and the explicit placeholder `none` for
    /// the pitch tracker (spec 04) and voicing (spec 05), which are not built yet.
    public static func timestampFeasibility(asrModelID: String) -> ConfigIdentity {
        ConfigIdentity(asrModelID: asrModelID, pitchTrackerID: "none", voicingID: "none")
    }
}

/// AMCore's `configDigest` together with the canonical JSON it hashes, so a reader can recompute it by hand.
public struct ConfigDigestRecord: Codable, Sendable, Equatable {
    public var canonicalJSON: String
    public var sha256: String

    /// The same `{config, thresholds}` value `configDigest` hashes.
    private struct Digested: Encodable {
        let config: ConfigIdentity
        let thresholds: Thresholds
    }

    public init(config: ConfigIdentity, thresholds: Thresholds = .current) throws {
        canonicalJSON = String(decoding: try CanonicalJSON.encode(Digested(config: config, thresholds: thresholds)),
                               as: UTF8.self)
        sha256 = try configDigest(config, thresholds: thresholds)
        guard Digest.sha256(canonicalJSON) == sha256 else {
            throw ModelVerificationError.manifestInconsistent(computed: Digest.sha256(canonicalJSON), recorded: sha256)
        }
    }

    /// The shell recipe, for recomputing by hand from the report JSON.
    public static let recipe =
        #"printf '%s' "$(plutil -extract identity.configCanonicalJSON raw -o - <report>.json)" | shasum -a 256"#
}

public enum SourceTree {
    /// Entries under this folder are left out of `sourceTreeHash`, so a report can sit in a descendant commit.
    public static let reportsFolder = "docs/agreement/reports/"

    /// The shell recipe, for recomputing by hand.
    public static let recipe =
        #"git ls-tree -r --full-tree <commit> | grep -v "$(printf '\t')docs/agreement/reports/" | LC_ALL=C sort | shasum -a 256"#

    /// `sourceTreeHash`: SHA-256 of the `git ls-tree -r --full-tree <commit>` lines, without entries under
    /// `docs/agreement/reports/`, sorted bytewise, each ending in a newline.
    public static func hash(lsTree output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            .filter { line in
                guard let tab = line.firstIndex(of: "\t") else { return true }
                return !line[line.index(after: tab)...].hasPrefix(reportsFolder)
            }
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        return Digest.sha256(lines.map { $0 + "\n" }.joined())
    }
}

public enum CorpusHash {
    /// The shell recipe, for recomputing by hand from the cache folder.
    public static let recipe = "shasum -a 256 <clip files> | cut -d' ' -f1 | LC_ALL=C sort | shasum -a 256"

    /// The corpus manifest hash: SHA-256 of the sorted file hashes, one per line, each ending in a newline.
    public static func hash(fileSHA256s: [String]) -> String {
        Digest.sha256(fileSHA256s.sorted().map { $0 + "\n" }.joined())
    }
}
