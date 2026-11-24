// Spec 11 §4a/§4b/§4c: the VCTK side of the anti-inconclusive guard runs on the trimmed positive-set clips (tuning
// speakers while tuning, held-out speakers for the release). This writes what MFA and `am-timestamps spec11-guard`
// read: the clip list, an MFA input corpus (each clip's audio linked next to its phrase text as `.lab`) and the
// guard's inputs JSON. Local only; it reads caches and writes under the given folder, never into the repository.

import AMEvaluation
import Foundation

/// One clip the guard compares: its id, audio file and the phrase text every reader read.
struct GuardInput: Codable {
    let clipID: String
    let audio: String
    let transcript: String
}

func guardInputs(_ args: Arguments, root: URL) throws -> Int32 {
    let scope = try args.required("scope")
    let out = try args.url("out")
    let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
    let cacheDir = args.value("vctk").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkCache)
    guard let cache = PositiveCache(cacheDir) else {
        throw CLIError.failed("no trimmed VCTK cache at \(cacheDir.path) (scripts/fetch-vctk-eval.sh)")
    }
    let table = try VCTKSubPhraseTable.load(root.appendingPathComponent(Paths.subPhrases))
    let phrases = try PositivePhrases(root: root, manifest: manifest, table: table)
    let evaluation = Set(table.evaluationPhrases)
    let speakers: Set<String> = switch scope {
    case "tuning": Set(manifest.tuningSpeakers.map(\.id))
    case "held-out": Set(manifest.heldOutSpeakers.map(\.id))
    default: throw CLIError.usage("guard-inputs --scope tuning|held-out --out <dir>")
    }
    let clips = cache.kept.filter { speakers.contains($0.speaker) && evaluation.contains($0.phrase) }
        .sorted { ($0.speaker, $0.phrase) < ($1.speaker, $1.phrase) }
    let corpus = out.appendingPathComponent("corpus")
    try? FileManager.default.removeItem(at: corpus)
    var inputs: [GuardInput] = []
    for clip in clips {
        guard let text = phrases.text(of: clip.phrase) else { continue }
        let id = "\(clip.speaker)_\(clip.phrase)"
        let audio = vctkAudio(cacheDir, speaker: clip.speaker, phrase: clip.phrase).resolvingSymlinksInPath()
        let dir = corpus.appendingPathComponent(clip.speaker)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("\(id).flac"), withDestinationURL: audio)
        try Data((text + "\n").utf8).write(to: dir.appendingPathComponent("\(id).lab"))
        inputs.append(GuardInput(clipID: id, audio: audio.path, transcript: text))
    }
    // Rewritten only when it changes: scripts/spec11-guard.sh re-runs MFA when clips.txt is newer than its output.
    let list = Data((inputs.map(\.clipID).joined(separator: "\n") + "\n").utf8)
    let listURL = out.appendingPathComponent("clips.txt")
    if (try? Data(contentsOf: listURL)) != list { try list.write(to: listURL) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(inputs).write(to: out.appendingPathComponent("inputs.json"))
    print("guard-inputs: \(scope): \(inputs.count) clips of \(speakers.count) speakers → \(out.path)")
    return 0
}
