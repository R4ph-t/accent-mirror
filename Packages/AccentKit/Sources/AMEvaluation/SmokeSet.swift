// The fixed smoke set (plan §6.3a): committed under `fixtures/smoke/` as 16 kHz FLAC, ≤ 5 MB, with a manifest of file
// hashes. This spec checks the manifest, the size cap and the load time; it never asserts rates and never counts
// toward a gate. Golden verdicts and digests come in specs 08 and 10.

import Foundation
import AMCore

public struct SmokeManifest: Sendable, Hashable, Codable {
    public struct Word: Sendable, Hashable, Codable {
        /// speechocean762 word id (`<utterance>#<index>`).
        public let id: String
        public let text: String
        /// `stressWrong` (≥ 4 of 5 raters, polysyllabic, intelligible) or `stressCorrect` (unanimous).
        public let label: String
    }

    public struct File: Sendable, Hashable, Codable {
        /// Relative to `fixtures/smoke/`.
        public let path: String
        public let sha256: String
        public let bytes: Int
        /// `speechocean762` or `vctk`.
        public let corpus: String
        public let speaker: String
        /// speechocean762 utterance id or VCTK phrase id.
        public let item: String
        /// The labelled words this utterance carries (speechocean762 only).
        public let words: [Word]
    }

    public let version: Int
    public let seed: UInt64
    public let files: [File]

    /// The size cap (§6.3a), read as decimal megabytes: 5,000,000 bytes for everything under `fixtures/smoke/`.
    public static let maximumBytes = 5_000_000

    public var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }

    public static func load(_ url: URL) throws -> SmokeManifest {
        try JSONDecoder().decode(SmokeManifest.self, from: Data(contentsOf: url))
    }

    /// Every problem with the files on disk under `directory`: missing, wrong size or wrong hash.
    public func problems(in directory: URL) -> [String] {
        var out: [String] = []
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            guard let data = try? Data(contentsOf: url) else {
                out.append("\(file.path): missing")
                continue
            }
            if data.count != file.bytes { out.append("\(file.path): \(data.count) bytes, manifest says \(file.bytes)") }
            if SHA256Digest.hex(of: data) != file.sha256 { out.append("\(file.path): SHA-256 mismatch") }
        }
        return out
    }
}
