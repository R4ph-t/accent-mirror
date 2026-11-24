// CTO ruling 2026-11-24 on #27: spec 23 merges measurement-only. b2 (`ctc-w2v2b960-1`) is evaluation tooling and must
// not be reachable from the shipped analysis; the shipped aligner is `whisper`. These tests read the source tree (no
// network, no models) and fail if AMPipeline's dependency closure or the app target ever reaches the CTC aligner, or
// if CTC weights land where the app copies resources.

import AMAlignment
import AMCore
import AMPipeline
import Foundation
import Testing

@Suite("Shipped aligner is Whisper-only (spec 23, measurement-only)")
struct ShippedAlignerTests {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AMPipelineTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // AccentKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
    static let package = repo.appendingPathComponent("Packages/AccentKit")

    /// The tooling-only target that holds b2.
    static let ctcTarget = "AMAlignmentCTC"
    /// What shipped code must never mention: the CTC target and its types, and b2's aligner ID as a string literal.
    static let forbidden = [ctcTarget, "CTCAligner", "CTCForcedAlignment", "CTCModelManifest", "\"ctc-w2v2b960-1\""]

    // MARK: - (1) the shipped identity

    @Test("the shipped config identity records the whisper aligner and no aligner model")
    func shippedIdentityIsWhisper() {
        let identity = ShippedConfig.identity(asrModelID: "whisperkit-base.en")
        #expect(identity.aligner == "whisper")
        #expect(identity.aligner == WhisperOnly.aligner)
        #expect(identity.alignerModelSHA256 == "none")
        #expect(ShippedConfig.wordBoundaryRefiner.id == "whisper")
        #expect(ShippedConfig.wordBoundaryRefiner is WhisperOnly)
        #expect(identity.thresholdsVersion == Versions.thresholdsVersion)
        #expect(identity.contractVersion == Versions.contractVersion)
    }

    @Test("the shipped refiner leaves Whisper's word timings as recognised")
    func shippedRefinerKeepsTimings() async throws {
        let words = [
            WordTimestamp(word: "record", start: 0.12, end: 0.58, probability: 0.9),
            WordTimestamp(word: "it", start: 0.61, end: 0.74, probability: 0.8),
        ]
        let refined = try await ShippedConfig.wordBoundaryRefiner.refine(
            words, samples: [Float](repeating: 0.1, count: 16_000), sampleRate: 16_000)
        #expect(refined == words)
    }

    // MARK: - (2) the package graph

    @Test("AMPipeline's dependency closure in Package.swift excludes the CTC target")
    func packageGraphExcludesCTC() throws {
        let manifest = try String(contentsOf: Self.package.appendingPathComponent("Package.swift"), encoding: .utf8)
        let graph = PackageGraph(manifest)
        // The parser must see the real graph, or the check below is vacuous.
        #expect(graph.dependencies["AMPipeline"]?.contains("AMAlignment") == true)
        #expect(graph.dependencies[Self.ctcTarget] == ["AMCore", "AMAlignment"])
        #expect(graph.dependencies["am-timestamps"]?.contains(Self.ctcTarget) == true)

        let closure = graph.closure(of: "AMPipeline")
        #expect(closure.contains("AMScoring") && closure.contains("AMProsody"))
        #expect(!closure.contains(Self.ctcTarget), "AMPipeline (what the app links) must not reach \(Self.ctcTarget)")
        #expect(!graph.libraryModules.contains(Self.ctcTarget), "\(Self.ctcTarget) must not be a library product")
    }

    @Test("the graph check catches the CTC target added back to the shipped closure")
    func packageGraphCatchesPlantedDependency() {
        let planted = """
            let modules: [(name: String, dependencies: [String])] = [
                ("AMCore", []),
                ("AMAlignment", ["AMCore"]),
                ("AMProsody", ["AMCore", "AMAlignment"]),
                ("AMPipeline", ["AMCore", "AMProsody"]),
            ]
            targets: [
                .target(name: "AMAlignmentCTC", dependencies: ["AMCore", "AMAlignment"]),
            ]
            """
        #expect(!PackageGraph(planted).closure(of: "AMPipeline").contains(Self.ctcTarget))
        let reached = planted.replacingOccurrences(
            of: "(\"AMProsody\", [\"AMCore\", \"AMAlignment\"])",
            with: "(\"AMProsody\", [\"AMCore\", \"AMAlignment\", \"AMAlignmentCTC\"])")
        #expect(PackageGraph(reached).closure(of: "AMPipeline").contains(Self.ctcTarget))
        #expect(PackageGraph(planted + "\n(\"AMAlignmentCTC\", [\"AMCore\"]),").libraryModules.contains(Self.ctcTarget))
    }

    // MARK: - (2) the shipped sources

    /// Every Swift file in AMPipeline's closure and the app target.
    static func shippedSources() throws -> [URL] {
        let manifest = try String(contentsOf: package.appendingPathComponent("Package.swift"), encoding: .utf8)
        let roots = PackageGraph(manifest).closure(of: "AMPipeline").sorted()
            .map { package.appendingPathComponent("Sources/\($0)") } + [repo.appendingPathComponent("AccentMirror")]
        return roots.flatMap(swiftFiles)
    }

    static func swiftFiles(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The files under `files` that mention a forbidden name, with the name.
    static func violations(in files: [URL]) throws -> [String] {
        try files.flatMap { file -> [String] in
            let text = try String(contentsOf: file, encoding: .utf8)
            return forbidden.filter { text.contains($0) }.map { "\(file.lastPathComponent): \($0)" }
        }
    }

    @Test("no source in AMPipeline's closure or the app target references the CTC aligner")
    func shippedSourcesNeverReferenceCTC() throws {
        let files = try Self.shippedSources()
        // AMPipeline, its eight modules and the app: a walk that finds nothing would prove nothing.
        #expect(files.contains { $0.lastPathComponent == "ShippedConfig.swift" })
        #expect(files.contains { $0.path.contains("/AccentMirror/") })
        #expect(files.count > 50)
        #expect(try Self.violations(in: files) == [])
    }

    @Test("the source check catches a planted reference to the CTC aligner")
    func sourceCheckCatchesPlantedReference() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clean = root.appendingPathComponent("Clean.swift")
        try Data("// The aligner is `whisper`; `ctc-w2v2b960-1` is tooling.\nlet id = \"whisper\"\n".utf8).write(to: clean)
        #expect(try Self.violations(in: [clean]) == [])
        for (index, line) in ["import AMAlignmentCTC", "let a = try await CTCAligner.load()", "let id = \"ctc-w2v2b960-1\""]
            .enumerated()
        {
            let planted = root.appendingPathComponent("Planted\(index).swift")
            try Data((line + "\n").utf8).write(to: planted)
            #expect(try Self.violations(in: [planted]).count >= 1, "\(line)")
        }
    }

    // MARK: - (b) no CTC weights where the app copies resources

    @Test("nothing the app bundles or fetches holds CTC weights or their manifest")
    func appResourcesHoldNoCTC() throws {
        let manifest = try String(contentsOf: Self.package.appendingPathComponent("Package.swift"), encoding: .utf8)
        // The app's own resources, the bundled model manifests, and each shipped module's SPM resources.
        let roots = [Self.repo.appendingPathComponent("AccentMirror"), Self.repo.appendingPathComponent("Resources")]
            + PackageGraph(manifest).closure(of: "AMPipeline").map {
                Self.package.appendingPathComponent("Sources/\($0)/Resources")
            }
        var files: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            files += walker.compactMap { $0 as? URL }
        }
        #expect(files.count > 10)
        let names = files.map { String($0.path.dropFirst(Self.repo.path.count)).lowercased() }.filter {
            $0.contains("wav2vec") || $0.contains("ctc") || $0.hasSuffix(".mlpackage")
        }
        #expect(names == [], "CTC files where the app copies resources")
        for file in files where file.lastPathComponent == "manifest.json" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("wav2vec2"), "\(file.path) names the CTC model")
        }
        // The app's build spec never names the CTC model, its fetch script or its target.
        let spec = try String(contentsOf: Self.repo.appendingPathComponent("project.yml"), encoding: .utf8)
        for name in ["wav2vec", "fetch-ctc", Self.ctcTarget] { #expect(!spec.contains(name), "project.yml: \(name)") }
    }
}

/// A small reading of Package.swift: the `modules` tuples (each also a library product) and the `.target(...)` and
/// `.executableTarget(...)` declarations with their local dependencies.
struct PackageGraph {
    var dependencies: [String: [String]] = [:]
    var libraryModules: Set<String> = []

    init(_ manifest: String) {
        let quoted = #/"([A-Za-z0-9_-]+)"/#
        func names(_ list: Substring) -> [String] { list.matches(of: quoted).map { String($0.output.1) } }
        for match in manifest.matches(of: #/\(\s*"([A-Za-z0-9_-]+)"\s*,\s*\[([^\]]*)\]\s*\)/#) {
            let name = String(match.output.1)
            dependencies[name] = names(match.output.2)
            libraryModules.insert(name)
        }
        let target = #/\.(?:target|executableTarget)\(\s*name:\s*"([A-Za-z0-9_-]+)"\s*,\s*dependencies:\s*\[([^\]]*)\]/#
        for match in manifest.matches(of: target) {
            dependencies[String(match.output.1)] = names(match.output.2)
        }
    }

    /// `module` and everything it depends on, transitively.
    func closure(of module: String) -> Set<String> {
        var seen: Set<String> = []
        var queue = [module]
        while let next = queue.popLast() {
            guard seen.insert(next).inserted else { continue }
            queue += dependencies[next] ?? []
        }
        return seen
    }
}
