import Foundation
import AMEvaluation

/// A synthetic eval-speakers manifest: 18 tuning and 12 held-out speakers, every phrase present.
enum SyntheticVCTK {
    static func manifest(tuning: Int = 18, heldOut: Int = 12) throws -> VCTKEvalSpeakersManifest {
        func entry(_ speaker: String, split: String?, gender: String) -> [String: Any] {
            var e: [String: Any] = [
                "speaker": speaker, "accent": "English", "gender": gender,
                "files": Dictionary(uniqueKeysWithValues: VCTK.phrases.map { ($0, String(repeating: "0", count: 64)) }),
            ]
            if let split { e["split"] = split }
            return e
        }
        let speakers = (0..<(tuning + heldOut)).map { i in
            entry("p\(400 + i)", split: i < tuning ? "tuning" : "heldOut", gender: i % 2 == 0 ? "F" : "M")
        }
        let object: [String: Any] = [
            "corpus": "VCTK 0.92", "seed": 1, "phrases": VCTK.phrases,
            "bundled": VCTK.bundledVoices.map { entry($0, split: nil, gender: "F") }, "speakers": speakers,
            "tuningCount": tuning, "heldOutCount": heldOut,
        ]
        return try JSONDecoder().decode(
            VCTKEvalSpeakersManifest.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func allClips(_ manifest: VCTKEvalSpeakersManifest) -> Set<VCTKClip> {
        Set((manifest.bundled + manifest.speakers).flatMap { e in VCTK.phrases.map { VCTKClip(speaker: e.speaker, phrase: $0) } }
            .filter { !($0.speaker == "p225" && $0.phrase == "015") })
    }
}
