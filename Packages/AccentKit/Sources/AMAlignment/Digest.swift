import CryptoKit
import Foundation

/// SHA-256 helpers shared by model verification, replay manifests and the evaluation reports.
public enum Digest {
    /// Lower-case hex SHA-256 of `data`.
    public static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// Lower-case hex SHA-256 of a UTF-8 string.
    public static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    /// Lower-case hex SHA-256 of a file, read in 1 MiB chunks.
    public static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    /// The digest of a file listing: SHA-256 of the `shasum -a 256` lines (`<sha256>  <path>\n`), sorted by path
    /// bytewise. The same as `shasum -a 256 <paths, sorted> | shasum -a 256` run in the listing's root folder.
    public static func listing(_ entries: [(path: String, sha256: String)]) -> String {
        let lines = entries
            .sorted { Array($0.path.utf8).lexicographicallyPrecedes(Array($1.path.utf8)) }
            .map { "\($0.sha256)  \($0.path)\n" }
        return sha256(lines.joined())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
