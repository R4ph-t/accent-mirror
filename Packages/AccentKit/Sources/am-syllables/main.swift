// Spec 07 local tooling: writes the syllable-boundary report. Never run by the app, CI or `make check`; it reads no
// corpus and makes no network call. Until spec 23 ships a refiner the real-speech lines are NOT EVALUATED.
//
//   am-syllables report --repo <root> --out <dir>

import AMCore
import AMSyllableEval
import Foundation

func shell(_ arguments: String..., in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let usage = "usage: am-syllables report --repo <root> --out <dir>"
var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "report" else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
var options: [String: String] = [:]
arguments.removeFirst()
while arguments.count >= 2, arguments[0].hasPrefix("--") {
    options[String(arguments[0].dropFirst(2))] = arguments[1]
    arguments.removeFirst(2)
}
guard let repo = options["repo"].map({ URL(filePath: $0) }), let out = options["out"].map({ URL(filePath: $0) }),
    arguments.isEmpty
else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}

do {
    let commit = try shell("git", "rev-parse", "HEAD", in: repo)
    let clean = try shell("git", "status", "--porcelain", in: repo).isEmpty
    let identity = try SyllableBoundaryReport.Identity(
        config: .syllableSegmentation, evaluatedCommit: commit, cleanTree: clean)
    let report = SyllableBoundaryReport(identity: identity, evaluation: nil)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let json = out.appending(path: report.fileStem + ".json"), markdown = out.appending(path: report.fileStem + ".md")
    try report.json().write(to: json)
    try Data(report.markdown().utf8).write(to: markdown)
    for line in report.lines {
        print("\(line.name) [\(line.bar)]: \(line.note ?? line.status.rawValue)")
    }
    print("Report: \(report.status.rawValue) -> \(json.path(percentEncoded: false)), \(markdown.lastPathComponent)")
} catch {
    FileHandle.standardError.write(Data("am-syllables: \(error)\n".utf8))
    exit(1)
}
