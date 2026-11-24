import Foundation
import Testing

/// The names Samples ▸ lists, read from the committed fixtures. No app host, no windows.
struct FixtureLibraryTests {
    /// `AccentMirror/Resources/Fixtures`, found from this file so no machine path is baked in.
    private let library = FixtureLibrary(root: URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory))

    @Test func listsEveryStateSortedAndUnique() throws {
        let names = try library.allNames()
        #expect(!names.isEmpty)
        #expect(names == names.sorted())
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.hasSuffix(".json") })
    }

    @Test(arguments: ["empty", "result", "analysing"])
    func includesCoreStates(_ name: String) throws {
        #expect(try library.allNames().contains(name))
    }

    /// Every menu item must open: each listed state loads with its phrase and take.
    @Test func everyListedStateLoads() throws {
        for name in try library.allNames() {
            #expect(throws: Never.self, "\(name)") { try library.load(name) }
        }
    }
}

/// Spec 28: the fixture schema accepts `{"notScored": {}}` and a missing verdict.
struct NotScoredFixtureTests {
    private let library = FixtureLibrary(root: URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory))

    @Test func notScoredVerdictDecodes() throws {
        let loaded = try library.load("result-not-scored")
        #expect(loaded.fixture.analysis?.verdict?.kind == .notScored)
    }

    @Test func missingVerdictDecodes() throws {
        let loaded = try library.load("result-no-verdict")
        #expect(loaded.fixture.analysis != nil)
        #expect(loaded.fixture.analysis?.verdict == nil)
    }

    @Test func kindNotScoredDecodes() throws {
        let verdict = try JSONDecoder().decode(Verdict.self, from: Data(#"{"kind": "notScored"}"#.utf8))
        #expect(verdict.kind == .notScored)
    }

    /// Spec 29: every fixture's analysed state is `.notScored` (or carries no verdict at all).
    @Test func everyAnalysedFixtureIsNotScored() throws {
        for name in try library.allNames() {
            let analysis = try library.load(name).fixture.analysis
            #expect(analysis?.verdict == nil || analysis?.verdict?.kind == .notScored, "\(name)")
        }
    }
}

/// Spec 28: the presenter and the copy read no verdict. Reads the two source files (found from #filePath); no app host.
struct PresenterSourceTests {
    private let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "AccentMirror/Fixtures", directoryHint: .isDirectory)

    @Test(arguments: ["ShellPresenter.swift", "Copy.swift", "ResultLogic.swift"])
    func noVerdictTypes(_ file: String) throws {
        let text = try String(contentsOf: fixtures.appending(path: file), encoding: .utf8)
        #expect(text.contains("enum"), "the scan must read the file")
        for name in ["Verdict", "DiffRow", "StressLine", "MeasureState", "NoClearDifferenceReason", "Inconclusive"] {
            #expect(text.firstMatch(of: try Regex("\\b\(name)\\b")) == nil, "\(file) references \(name)")
        }
        #expect(!text.contains(".verdict"), "\(file) reads .verdict")
        #expect(!text.contains(".stress?") && !text.contains("analysis?.measures"), "\(file) reads stress lines or measures")
    }
}
