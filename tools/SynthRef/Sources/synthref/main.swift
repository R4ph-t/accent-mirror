// synthref (spec 22): synthetic native references, evaluation only. Never linked by the app or AccentKit.
//
//   synthref voices                       list installed English voices (nothing is downloaded or spoken)
//   synthref run [options]                verify voices on the verification items, then check (ii) and the
//                                         synthetic negative set; writes eval-cache/tts/reports/ and
//                                         fixtures/tts/digests.json
//     --offline                           force the Mac fallback
//     --elevenlabs-voice <id>             an ElevenLabs voice to verify (repeatable; used only with a key)
//     --mac-voice <identifier>            limit the Mac fallback to these Premium voices (repeatable)
//     --vctk <dir> --vctk-timings <dir> --speechocean <dir> --speechocean-timings <dir>
//   synthref tts-reference --phrases <file> --voice <identifier> --out <dir>
//                                         spec 23's reference sanity check: speak each phrase with SSML marks
//                                         around every word; write an MFA corpus and markers.json. Exit 3 when
//                                         the voice is missing (scripts/reference-check.sh)
//
// The ElevenLabs key is read only from ELEVENLABS_API_KEY in the environment and is never printed or written.

import Foundation
import SynthRefKit

func repositoryRoot() -> URL {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while url.path != "/" {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("fixtures/vctk/eval-speakers.json").path) {
            return url
        }
        url.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

let arguments = Array(CommandLine.arguments.dropFirst())
func values(_ name: String) -> [String] {
    arguments.indices.filter { arguments[$0] == name && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
}

switch arguments.first {
case "voices":
    for voice in InstalledVoices.english() { print(voice.line) }
    let premium = InstalledVoices.fallbackCandidates(InstalledVoices.english())
    print(premium.isEmpty ? "Premium English voices: none (the Mac fallback is NOT EVALUATED)"
          : "Premium English voices: \(premium.count)")
case "run":
    var options = RunOptions(repositoryRoot: repositoryRoot())
    options.offline = arguments.contains("--offline")
    options.elevenLabsVoices = values("--elevenlabs-voice")
    options.macVoices = values("--mac-voice")
    if let v = values("--vctk").first { options.vctk = URL(fileURLWithPath: v) }
    if let v = values("--vctk-timings").first { options.vctkTimings = URL(fileURLWithPath: v) }
    if let v = values("--speechocean").first { options.speechOcean = URL(fileURLWithPath: v) }
    if let v = values("--speechocean-timings").first { options.speechOceanTimings = URL(fileURLWithPath: v) }
    var run = SynthRefRun(options: options)
    do {
        _ = try await run.run()
        print("report: \(try run.writeReport().path)")
    } catch {
        FileHandle.standardError.write(Data("synthref: \(error)\n".utf8))
        exit(1)
    }
case "tts-reference":
    guard let phrases = values("--phrases").first, let voice = values("--voice").first, let out = values("--out").first
    else {
        print("usage: synthref tts-reference --phrases <file> --voice <identifier> --out <dir>")
        exit(64)
    }
    do {
        let line = try await MarkedReference.write(
            phrasesFile: URL(fileURLWithPath: phrases), voiceID: voice, out: URL(fileURLWithPath: out))
        print("tts-reference: \(line)")
    } catch MarkedReference.Failure.voiceMissing(let id) {
        print("tts-reference: SKIPPED, voice \(id) is not installed on this Mac")
        exit(3)
    } catch {
        FileHandle.standardError.write(Data("synthref: \(error)\n".utf8))
        exit(1)
    }
default:
    print("usage: synthref voices | synthref tts-reference --phrases <file> --voice <id> --out <dir> | synthref run [--offline] [--elevenlabs-voice <id>]... [--mac-voice <id>]...")
    exit(arguments.first == "help" ? 0 : 64)
}
