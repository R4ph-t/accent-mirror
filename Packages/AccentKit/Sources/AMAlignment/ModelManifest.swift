import Foundation

/// The pinned description of a speech model's files (`Resources/Models/<model>/manifest.json`).
/// `scripts/fetch-models.sh` fetches the files it lists; `verify(folder:)` checks them before any load.
public struct ModelManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        /// Path inside the fetched model folder, e.g. `model/TextDecoder.mlmodelc/weights/weight.bin`.
        public var path: String
        public var size: Int
        public var sha256: String
        /// Where the file is fetched from, pinned to an upstream commit (never a branch).
        public var url: String

        public init(path: String, size: Int, sha256: String, url: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
            self.url = url
        }
    }

    public struct Source: Codable, Sendable, Equatable {
        public var role: String
        public var repo: String
        public var commit: String
        public var folder: String?
        public var license: String
    }

    public struct Package: Codable, Sendable, Equatable {
        public var package: String
        public var version: String
        public var commit: String
        public var license: String
    }

    public var formatVersion: Int
    public var model: String
    public var asrModelID: String
    /// `Digest.listing` over every file's SHA-256.
    public var modelSHA256: String
    public var whisperKit: Package
    public var sources: [Source]
    public var files: [File]

    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
    }

    /// The files of the model proper (Core ML), relative to the fetched folder.
    public static let modelSubfolder = "model"
    /// The tokenizer files, relative to the fetched folder.
    public static let tokenizerSubfolder = "tokenizer"

    /// Checks that the manifest is self-consistent and that `folder` holds exactly the pinned bytes of every file.
    /// Throws the first problem found; on success the folder is safe to load.
    public func verify(folder: URL) throws {
        let listed = Digest.listing(files.map { ($0.path, $0.sha256) })
        guard listed == modelSHA256 else {
            throw ModelVerificationError.manifestInconsistent(computed: listed, recorded: modelSHA256)
        }
        guard asrModelID.hasSuffix("#" + modelSHA256.prefix(8)) else {
            throw ModelVerificationError.manifestInconsistent(computed: String(modelSHA256.prefix(8)), recorded: asrModelID)
        }
        for file in files {
            let url = folder.appending(path: file.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ModelVerificationError.missing(path: file.path)
            }
            let actual = try Digest.sha256(fileAt: url)
            guard actual == file.sha256 else {
                throw ModelVerificationError.mismatch(path: file.path, expected: file.sha256, actual: actual)
            }
        }
    }
}

public enum ModelVerificationError: Error, Equatable, Sendable {
    case manifestInconsistent(computed: String, recorded: String)
    case missing(path: String)
    case mismatch(path: String, expected: String, actual: String)
}
