import AMAlignment
import AMTimestampEval
import Foundation

/// `--key value` options and bare `--flag`s.
struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ arguments: ArraySlice<String>) throws {
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--") else { throw ToolError.usage("unexpected argument \(argument)") }
            let key = String(argument.dropFirst(2))
            if let next = rest.first, !next.hasPrefix("--") {
                values[key] = next
                rest = rest.dropFirst()
            } else {
                flags.insert(key)
            }
        }
    }

    func string(_ key: String) throws -> String {
        guard let value = values[key] else { throw ToolError.usage("missing --\(key)") }
        return value
    }

    func optional(_ key: String) -> String? { values[key] }

    func url(_ key: String) throws -> URL { URL(filePath: try string(key)) }

    func flag(_ key: String) -> Bool { flags.contains(key) }
}

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case failed(String)

    var description: String {
        switch self {
        case .usage(let message): "usage: \(message)"
        case .failed(let message): message
        }
    }
}

/// One clip of the evaluation set, with its files in the VCTK cache.
struct Clip {
    var id: String
    var speaker: String
    var audio: URL
    var transcript: URL

    /// Reads `fixtures/vctk/starter-clips.txt` (`<speaker>_<text id>` per line, `#` comments).
    static func load(list: URL, corpus: URL) throws -> [Clip] {
        try String(contentsOf: list, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { id in
                let speaker = String(id.prefix { $0 != "_" })
                return Clip(
                    id: id, speaker: speaker,
                    audio: corpus.appending(path: "wav48_silence_trimmed/\(speaker)/\(id)_mic1.flac"),
                    transcript: corpus.appending(path: "txt/\(speaker)/\(id).txt"))
            }
    }

    /// The official transcript, verbatim except for the trailing line break.
    func text() throws -> String {
        var text = try String(contentsOf: transcript, encoding: .utf8)
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}

/// Runs a tool and returns its standard output (standard error is merged), trimmed.
@discardableResult
func shell(_ arguments: String..., in directory: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw ToolError.failed("\(arguments.joined(separator: " ")) failed: \(output)")
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try (encoder.encode(value) + Data("\n".utf8)).write(to: url, options: .atomic)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("am-timestamps: \(message)\n".utf8))
}

let vctkAttribution = "Audio and transcripts from CSTR VCTK Corpus 0.92 (Yamagishi, Veaux, MacDonald; University of "
    + "Edinburgh, Centre for Speech Technology Research), CC BY 4.0, https://doi.org/10.7488/ds/2645"
