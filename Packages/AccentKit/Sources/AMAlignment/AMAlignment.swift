// AMAlignment: from phrase text and heard words to expected pronunciations and a `WordAlignment` (spec 06).
// Everything here runs on device from bundled resources: CMUdict, the stress-shift pairs and the word lists.

import Foundation
import AMCore

/// Identifies the `AMAlignment` module and the modules it may depend on.
public enum AMAlignmentModule {
    public static let name = "AMAlignment"
    public static let dependencies: [String] = [AMCoreModule.name]
}

/// A bundled resource is missing or can't be read. Only a broken build produces this.
public enum ResourceError: Error, Equatable, Sendable {
    case missing(String)
    case malformed(String)
}

enum BundledResource {
    static func url(_ path: String) throws(ResourceError) -> URL {
        guard let root = Bundle.module.resourceURL else { throw .missing(path) }
        // The package copies the `Resources` folder whole. Foundation reports a flat bundle's top-level `Resources`
        // as its resource URL (SwiftPM on macOS), while an Xcode-built bundle nests it in `Contents/Resources`.
        let candidates = [root.appending(path: "Resources").appending(path: path), root.appending(path: path)]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
        else { throw .missing(path) }
        return url
    }

    static func data(_ path: String) throws(ResourceError) -> Data {
        let url = try url(path)
        do { return try Data(contentsOf: url) } catch { throw .malformed(path) }
    }

    static func text(_ path: String) throws(ResourceError) -> String {
        String(decoding: try data(path), as: UTF8.self)
    }

    /// The non-empty lines of a list file, without `#` comment lines, trimmed.
    static func listLines(_ path: String) throws(ResourceError) -> [String] {
        try text(path).split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("#") ? nil : trimmed
        }
    }
}
