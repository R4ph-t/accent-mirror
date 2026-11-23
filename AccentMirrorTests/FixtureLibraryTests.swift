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

    @Test(arguments: ["empty", "close-all", "analysing"])
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
