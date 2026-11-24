import Foundation

/// A fixture with its phrase and take files resolved.
struct LoadedFixture: Sendable {
    var fixture: UIFixture
    var phrase: PhraseFixture
    var take: TakeFixture?
    /// `fixture.earlierTakes`, resolved, newest first.
    var earlierTakes: [TakeFixture] = []
}

/// Loads the committed JSON fixtures from the app bundle (`Contents/Resources/Fixtures/`). Bundle only:
/// no network, no user data.
struct FixtureLibrary: Sendable {
    var root: URL

    static let folderName = "Fixtures"
    /// Shown when the app launches without `-UIFixture`: the phrase with no takes yet.
    static let defaultFixture = "empty"

    init(root: URL) { self.root = root }

    init?(bundle: Bundle = .main) {
        guard let url = bundle.resourceURL?.appendingPathComponent(Self.folderName, isDirectory: true),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        root = url
    }

    /// Every fixture name, sorted, from `states/`.
    func allNames() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(at: root.appendingPathComponent("states"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func load(_ name: String) throws -> LoadedFixture {
        let fixture: UIFixture = try decode("states", name)
        guard fixture.name == name else { throw FixtureError.nameMismatch(file: name, declared: fixture.name) }
        let phrase: PhraseFixture = try decode("phrases", fixture.phrase)
        let take: TakeFixture? = try fixture.take.map { try decode("takes", $0) }
        let earlier: [TakeFixture] = try (fixture.earlierTakes ?? []).map { try decode("takes", $0) }
        return LoadedFixture(fixture: fixture, phrase: phrase, take: take, earlierTakes: earlier)
    }

    private func decode<T: Decodable>(_ folder: String, _ name: String) throws -> T {
        let url = root.appendingPathComponent(folder).appendingPathComponent(name + ".json")
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw FixtureError.unreadable(path: "\(folder)/\(name).json", underlying: String(describing: error))
        }
    }

    enum FixtureError: Error, CustomStringConvertible {
        case unreadable(path: String, underlying: String)
        case nameMismatch(file: String, declared: String)

        var description: String {
            switch self {
            case .unreadable(let path, let underlying): "Fixture \(path) could not be read: \(underlying)"
            case .nameMismatch(let file, let declared): "Fixture file \(file) declares the name \(declared)"
            }
        }
    }
}
