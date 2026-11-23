import AppKit
import Testing
@testable import AccentMirror

/// Renders every fixture × {light, dark} to `<fixture>-{light,dark}@2x.png` (2400 × 1600). Local only:
/// `make screenshots` runs it; CI and `make check` never do. No microphone, no audio, no network.
@MainActor
@Suite("Screenshots", .serialized)
struct ScreenshotTests {
    static var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("accent-mirror-screenshots")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test func renderAllFixtures() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary())
        let names = try library.allNames()
        #expect(!names.isEmpty)
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        defer { WindowRenderer.closeAll() }
        for name in names {
            let loaded = try library.load(name)
            for appearance in WindowRenderer.Appearance.allCases {
                let window = WindowRenderer.window(model: ShellModel(fixture: loaded), appearance: appearance)
                let png = try await WindowRenderer.capture(window)
                WindowRenderer.clear(window)
                try png.write(to: Self.outputDirectory.appendingPathComponent("\(name)-\(appearance.rawValue)@2x.png"))
            }
        }
    }
}
