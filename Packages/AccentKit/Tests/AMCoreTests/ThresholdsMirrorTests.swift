import Foundation
import Testing
import AMCore

/// `docs/thresholds.md` must mirror `Thresholds.current` exactly: one row per Swift value, same number.
@Suite("Thresholds mirror") struct ThresholdsMirrorTests {
    struct DocRow {
        let key: String
        let value: String
        let plan: String
        let line: Int
    }

    static let docURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AMCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // AccentKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("docs/thresholds.md")

    /// Rows of every table whose header has Key, Value and Plan columns.
    static func docRows() throws -> [DocRow] {
        let lines = try String(contentsOf: docURL, encoding: .utf8).components(separatedBy: "\n")
        var rows: [DocRow] = []
        var columns: [String: Int]?
        for (number, line) in lines.enumerated() {
            guard line.hasPrefix("|") else {
                columns = nil
                continue
            }
            let cells = cells(of: line)
            if columns == nil {
                let header = Dictionary(cells.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
                columns = header["Key"] != nil ? header : [:]
                continue
            }
            guard let columns, let key = columns["Key"], let value = columns["Value"], let plan = columns["Plan"],
                !cells[key].hasPrefix("---")
            else { continue }
            rows.append(DocRow(
                key: cells[key].trimmingCharacters(in: CharacterSet(charactersIn: "`")), value: cells[value],
                plan: cells[plan], line: number + 1))
        }
        return rows
    }

    /// Splits a Markdown table row on unescaped pipes.
    static func cells(of line: String) -> [String] {
        let placeholder = "\u{0}"
        let protected = line.replacingOccurrences(of: "\\|", with: placeholder)
        return protected.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map {
            $0.replacingOccurrences(of: placeholder, with: "|").trimmingCharacters(in: .whitespaces)
        }
    }

    /// `Thresholds.current` flattened to dotted keys, through its Codable form.
    static func swiftValues() throws -> [String: Double] {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Thresholds.current))
        var flat: [String: Double] = [:]
        func walk(_ node: Any, _ path: String) {
            if let dictionary = node as? [String: Any] {
                for (key, child) in dictionary { walk(child, path.isEmpty ? key : "\(path).\(key)") }
            } else if let number = node as? NSNumber {
                flat[path] = number.doubleValue
            } else {
                Issue.record("Thresholds.\(path) is not a number; the mirror only holds numbers")
            }
        }
        walk(object, "")
        return flat
    }

    @Test("every row has a key, a value and a plan section") func rowsAreComplete() throws {
        let rows = try Self.docRows()
        #expect(rows.count > 100)
        for row in rows {
            #expect(!row.key.isEmpty, "line \(row.line): no key")
            #expect(!row.plan.isEmpty, "line \(row.line): no plan section")
            #expect(Double(row.value) != nil, "line \(row.line): value '\(row.value)' is not a plain number")
        }
    }

    @Test("every row matches the Swift value") func rowsMatchSwift() throws {
        let swift = try Self.swiftValues()
        for row in try Self.docRows() {
            guard let expected = swift[row.key] else {
                Issue.record("line \(row.line): `\(row.key)` is not a property of Thresholds")
                continue
            }
            #expect(Double(row.value) == expected, "line \(row.line): doc says \(row.value), Swift says \(expected)")
        }
    }

    @Test("every Swift value has exactly one row") func swiftValuesAreAllDocumented() throws {
        let keys = try Self.docRows().map(\.key)
        for key in try Self.swiftValues().keys.sorted() {
            #expect(keys.filter { $0 == key }.count == 1, "`\(key)` needs exactly one row in docs/thresholds.md")
        }
    }
}
