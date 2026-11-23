// Canonical JSON (plan §6.6, §9.1): one byte-exact form per value, so digests agree across specs and machines.
//
// Rules:
// - object keys sorted by their UTF-8 bytes; no whitespace anywhere;
// - strings escape only `"`, `\` and control characters (`\b \f \n \r \t`, others as `\u00xx`); everything else is
//   raw UTF-8;
// - numbers: an integral value with |x| < 2^53 is written as an integer (`2`, `-60`); any other finite value uses
//   Swift's shortest round-trip form (`0.05`, `1e-07`); NaN and infinity are errors;
// - booleans and null as `true`, `false`, `null`.

import Foundation

public enum CanonicalJSON {
    public enum Failure: Error, Equatable {
        case nonFiniteNumber
        case unsupportedValue(String)
    }

    /// Canonical bytes of any `Encodable` value.
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.nonConformingFloatEncodingStrategy = .throw
        let plain = try encoder.encode(value)
        return try canonicalize(plain)
    }

    /// Canonical bytes of an existing JSON document (for example a golden file on disk).
    public static func canonicalize(_ json: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])
        var out = ""
        try write(object, into: &out)
        return Data(out.utf8)
    }

    /// Lowercase hex SHA-256 of the canonical form of `value`.
    public static func sha256(_ value: some Encodable) throws -> String {
        SHA256Digest.hex(of: try encode(value))
    }

    // MARK: - Writer

    private static func write(_ object: Any, into out: inout String) throws {
        switch object {
        case is NSNull:
            out += "null"
        case let string as String:
            writeString(string, into: &out)
        case let number as NSNumber:
            try writeNumber(number, into: &out)
        case let array as [Any]:
            out += "["
            for (i, element) in array.enumerated() {
                if i > 0 { out += "," }
                try write(element, into: &out)
            }
            out += "]"
        case let dictionary as [String: Any]:
            out += "{"
            let keys = dictionary.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (i, key) in keys.enumerated() {
                if i > 0 { out += "," }
                writeString(key, into: &out)
                out += ":"
                try write(dictionary[key]!, into: &out)
            }
            out += "}"
        default:
            throw Failure.unsupportedValue(String(describing: type(of: object)))
        }
    }

    private static func writeNumber(_ number: NSNumber, into out: inout String) throws {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            out += number.boolValue ? "true" : "false"
            return
        }
        let value = number.doubleValue
        guard value.isFinite else { throw Failure.nonFiniteNumber }
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
            out += String(Int64(value))
        } else {
            out += value.description
        }
    }

    private static func writeString(_ string: String, into out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
