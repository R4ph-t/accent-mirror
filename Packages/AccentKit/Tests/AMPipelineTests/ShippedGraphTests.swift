// Spec 28: the shipped app can't reach the verdict code, by the package graph, not by a flag. These read the source
// tree (Package.swift, project.yml, Swift sources) found from #filePath; nothing is edited.

import AMPipeline
import Foundation
import Testing

@Suite("Shipped graph excludes the verdict path (spec 28)") struct ShippedGraphTests {
    static let repo = ShippedAlignerTests.repo
    static let package = ShippedAlignerTests.package
    /// What the shipped graph must never reach.
    static let verdictModules: Set<String> = ["AMPlacement", "AMScoring", "AMVerdicts"]

    static func graph() throws -> PackageGraph {
        PackageGraph(try String(contentsOf: package.appendingPathComponent("Package.swift"), encoding: .utf8))
    }

    // MARK: - Package graph

    @Test("AMPipeline's transitive closure in Package.swift reaches no AMPlacement, AMScoring or AMVerdicts")
    func closureExcludesVerdictModules() throws {
        let graph = try Self.graph()
        let closure = graph.closure(of: "AMPipeline")
        // The parser must see the real graph, or the check is vacuous.
        #expect(closure.isSuperset(of: ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody", "AMWarp", "AMLibrary"]))
        #expect(graph.dependencies["AMVerdicts"]?.contains("AMScoring") == true)
        #expect(graph.dependencies["AMScoring"]?.contains("AMPlacement") == true)
        #expect(graph.dependencies["am-eval"]?.contains("AMVerdicts") == true)
        #expect(closure.isDisjoint(with: Self.verdictModules), "AMPipeline reaches \(closure.intersection(Self.verdictModules))")
        // AMPlacement is a leaf of the verdict path: it builds only on shipped modules.
        let placement = graph.closure(of: "AMPlacement").subtracting(["AMPlacement"])
        #expect(placement.isDisjoint(with: Self.verdictModules) && !placement.contains("AMPipeline"))
        #expect(!graph.closure(of: "AMScoring").contains("AMVerdicts"), "no cycle")
    }

    @Test("the closure check catches a verdict module planted two hops down")
    func closureCatchesPlantedTransitiveDependency() {
        let planted = PackageGraph("""
            let modules: [(name: String, dependencies: [String])] = [
                ("AMCore", []),
                ("AMPlacement", ["AMCore"]),
                ("AMProsody", ["AMCore", "AMPlacement"]),
                ("AMWarp", ["AMCore"]),
                ("AMPipeline", ["AMCore", "AMWarp", "AMProsody"]),
            ]
            """)
        #expect(planted.closure(of: "AMPipeline").contains("AMPlacement"))
        #expect(!(planted.dependencies["AMPipeline"] ?? []).contains("AMPlacement"), "only reachable transitively")
    }

    // MARK: - Sources

    static func swiftFiles(_ roots: [URL]) -> [URL] { roots.flatMap(ShippedAlignerTests.swiftFiles(under:)) }

    static let shippedRoots = [
        package.appendingPathComponent("Sources/AMPipeline"), repo.appendingPathComponent("AccentMirror"),
    ]
    static let forbiddenCalls = ["placementDecision(", "observedStress("]
    static let forbiddenImports = ["import AMPlacement", "import AMScoring", "import AMVerdicts"]

    static func violations(in files: [URL], of needles: [String]) throws -> [String] {
        try files.flatMap { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return needles.filter(text.contains).map { "\(url.lastPathComponent): \($0)" }
        }
    }

    @Test("no Swift file under AMPipeline or AccentMirror/ calls placementDecision( or observedStress(")
    func noPlacementCallsInShippedSources() throws {
        let files = Self.swiftFiles(Self.shippedRoots)
        #expect(files.count > 20, "the scan must see the sources")
        #expect(files.contains { $0.lastPathComponent == "Analyzer.swift" })
        #expect(files.contains { $0.lastPathComponent == "ShellPresenter.swift" })
        #expect(try Self.violations(in: files, of: Self.forbiddenCalls).isEmpty)
    }

    @Test("no Swift file under AccentMirror/ imports AMPlacement, AMScoring or AMVerdicts")
    func appImportsNoVerdictModule() throws {
        let files = Self.swiftFiles([Self.repo.appendingPathComponent("AccentMirror")])
        #expect(!files.isEmpty)
        #expect(try Self.violations(in: files, of: Self.forbiddenImports).isEmpty)
    }

    @Test("the source scan catches planted calls and imports") func scanCatchesPlanted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("am-graph-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Planted.swift")
        try "import AMVerdicts\nlet d = prominence.observedStress(of: w)\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try Self.violations(in: [file], of: Self.forbiddenCalls) == ["Planted.swift: observedStress("])
        #expect(try Self.violations(in: [file], of: Self.forbiddenImports) == ["Planted.swift: import AMVerdicts"])
    }

    // MARK: - The app target (project.yml, read only)

    /// The `dependencies:` entries of one target in project.yml, as "key: value" strings per entry.
    static func dependencies(ofTarget target: String, in yaml: String) -> [[String]] {
        let lines = yaml.components(separatedBy: "\n")
        func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
        guard let targets = lines.firstIndex(where: { $0 == "targets:" }) else { return [] }
        guard let start = lines[(targets + 1)...].firstIndex(where: { indent($0) == 2 && $0.trimmingCharacters(in: .whitespaces) == "\(target):" })
        else { return [] }
        let end = lines[(start + 1)...].firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty && indent($0) <= 2 }
            ?? lines.endIndex
        let block = Array(lines[(start + 1)..<end])
        guard let deps = block.firstIndex(where: { indent($0) == 4 && $0.trimmingCharacters(in: .whitespaces) == "dependencies:" })
        else { return [] }
        var entries: [[String]] = []
        for line in block[(deps + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if indent(line) <= 4 { break }
            if trimmed.hasPrefix("- ") {
                entries.append([String(trimmed.dropFirst(2))])
            } else if !entries.isEmpty {
                entries[entries.count - 1].append(trimmed)
            }
        }
        return entries
    }

    @Test("the app target AccentMirror links only the AMPipeline package product")
    func appLinksOnlyAMPipeline() throws {
        let yaml = try String(contentsOf: Self.repo.appendingPathComponent("project.yml"), encoding: .utf8)
        let entries = Self.dependencies(ofTarget: "AccentMirror", in: yaml)
        #expect(entries == [["package: AccentKit", "product: AMPipeline"]], "AccentMirror's dependencies: \(entries)")
    }

    @Test("the project.yml check catches a second AccentKit product on the app target")
    func projectCheckCatchesPlantedProduct() {
        let planted = """
            targets:
              AccentMirror:
                type: application
                dependencies:
                  - package: AccentKit
                    product: AMPipeline
                  - package: AccentKit
                    product: AMVerdicts
                settings:
                  base: {}
              AccentMirrorTests:
                dependencies:
                  - target: AccentMirror
            """
        let entries = Self.dependencies(ofTarget: "AccentMirror", in: planted)
        #expect(entries.count == 2)
        #expect(entries != [["package: AccentKit", "product: AMPipeline"]])
    }
}
