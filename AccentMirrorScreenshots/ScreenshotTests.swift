import AppKit
import Testing
@testable import AccentMirror

/// Renders every fixture × {light, dark} to `<fixture>-{light,dark}@2x.png` at 2× its window size (2400 × 1600 for
/// the default 1200 × 800 pt window). Local only: `make screenshots` runs it; CI and `make check` never do. No
/// microphone, no audio, no network.
///
/// One test case per fixture and appearance, run one after the other, so each case builds, captures and releases
/// its own window before the next one starts.
@MainActor
@Suite("Screenshots", .serialized)
struct ScreenshotTests {
    struct Frame: Sendable, CustomTestStringConvertible {
        var fixture: String
        var appearance: WindowRenderer.Appearance
        /// Spec 20: states with a `chart` block are rendered again with Reduce Motion forced on.
        var reduceMotion = false
        var name: String { reduceMotion ? "\(fixture)-reduce-motion" : fixture }
        var testDescription: String { "\(name)-\(appearance.rawValue)" }
    }

    /// Every committed fixture, light then dark, plus each motion state (`chart`) with Reduce Motion. Read from the
    /// app bundle, so a new fixture gets its frames for free.
    nonisolated static let frames: [Frame] = {
        let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))
        let names = (try? library?.allNames()) ?? []
        return names.flatMap { name in
            let motion = (try? library?.load(name))?.fixture.chart != nil
            return [false, true].filter { !$0 || motion }.flatMap { reduce in
                WindowRenderer.Appearance.allCases.map { Frame(fixture: name, appearance: $0, reduceMotion: reduce) }
            }
        }
    }()

    static var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("accent-mirror-screenshots")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test func everyFixtureHasFrames() {
        #expect(!Self.frames.isEmpty)
    }

    @Test(arguments: frames)
    func render(_ frame: Frame) async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let loaded = try library.load(frame.fixture)
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let size = WindowRenderer.pointSize(for: loaded.fixture)
        let model = ShellModel(fixture: loaded)
        // Motion frames follow the system's Reduce Motion unless forced, so every non-variant frame is rendered with
        // it off: the same PNGs on any machine.
        model.reduceMotionOverride = frame.reduceMotion
        let result = try await WindowRenderer.render(model: model, appearance: frame.appearance, size: size)
        // In the run's log: whether each window was freed before the next case (fixes round 5, item 3).
        print("[screenshots] \(frame.testDescription): window released \(result.released), app windows \(result.liveWindows)")
        try result.png.write(to: Self.outputDirectory.appendingPathComponent("\(frame.name)-\(frame.appearance.rawValue)@2x.png"))
    }
}
