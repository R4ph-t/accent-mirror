import Foundation
import AMEvaluation

/// Paths in the repository (fixtures are read from the source tree, never bundled).
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AMEvaluationTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // AccentKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func labels() throws -> SpeechOceanLabels {
        try SpeechOceanLabels.parseFixture(String(contentsOf: url("fixtures/speechocean762/labels.tsv"), encoding: .utf8))
    }

    static func pin(_ corpus: String, _ key: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url("fixtures/corpora/\(corpus).pin.json")))
        return (object as? [String: Any])?[key] as? String ?? ""
    }
}
