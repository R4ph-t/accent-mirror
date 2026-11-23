import Foundation
import Testing
import AMCore
import AMEvaluation

/// The committed smoke set and VCTK manifests. Never asserts rates; the smoke set never counts toward a gate.
@Suite("Committed fixtures") struct CommittedFixturesTests {
    static let smoke = Repo.url("fixtures/smoke")

    @Test("Smoke manifest: every file present with its hash, and everything under fixtures/smoke within 5 MB") func smokeManifest() throws {
        let manifest = try SmokeManifest.load(Self.smoke.appendingPathComponent("manifest.json"))
        #expect(manifest.problems(in: Self.smoke).isEmpty, "\(manifest.problems(in: Self.smoke))")
        let files = try FileManager.default.subpathsOfDirectory(atPath: Self.smoke.path)
        let total = try files.reduce(0) { sum, path in
            let attributes = try FileManager.default.attributesOfItem(atPath: Self.smoke.appendingPathComponent(path).path)
            return sum + ((attributes[.type] as? FileAttributeType) == .typeRegular ? (attributes[.size] as? Int ?? 0) : 0)
        }
        #expect(total <= SmokeManifest.maximumBytes)
        let audio = Set(files.filter { $0.hasPrefix("audio/") && $0.hasSuffix(".flac") })
        #expect(audio == Set(manifest.files.map(\.path)))
    }

    @Test("Smoke content: 20 stress-wrong and 100 stress-correct words from train speakers; 2 VCTK phrases × 3 tuning speakers")
    func smokeContent() throws {
        let manifest = try SmokeManifest.load(Self.smoke.appendingPathComponent("manifest.json"))
        let labels = try Repo.labels()
        let sets = SpeechOceanSets(labels: labels)
        let words = manifest.files.flatMap(\.words)
        #expect(words.filter { $0.label == "stressWrong" }.count == 20)
        #expect(words.filter { $0.label == "stressCorrect" }.count == 100)
        let byID = Dictionary(uniqueKeysWithValues: labels.words.map { ($0.id, $0) })
        for word in words {
            let label = try #require(byID[word.id])
            #expect(labels.half(of: label) == .train, "\(word.id)")
            #expect(label.isPolysyllabic && !label.isUnintelligible, "\(word.id)")
            #expect(word.label == "stressWrong" ? label.stressWrongVotes >= 4 : label.stressWrongVotes == 0, "\(word.id)")
        }
        #expect(Set(words.map(\.id)).isDisjoint(with: sets.cleanFalsePositive.map(\.id)))
        let vctk = manifest.files.filter { $0.corpus == "vctk" }
        let tuning = Set(try VCTKEvalSpeakersManifest.load(Repo.url("fixtures/vctk/eval-speakers.json")).tuningSpeakers.map(\.id))
        #expect(vctk.count == 6 && Set(vctk.map(\.item)).count == 2 && Set(vctk.map(\.speaker)).count == 3)
        #expect(Set(vctk.map(\.speaker)).isSubset(of: tuning))
    }

    @Test("Smoke set loads in under a minute") func smokeLoads() throws {
        let manifest = try SmokeManifest.load(Self.smoke.appendingPathComponent("manifest.json"))
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for file in manifest.files {
                let (samples, rate) = try AudioFiles.readMono(Self.smoke.appendingPathComponent(file.path))
                #expect(rate == 16_000 && !samples.isEmpty)
            }
        }
        #expect(elapsed < .seconds(Thresholds.current.agreement.smokeSetMaxSeconds))
    }

    @Test("ATTRIBUTION names both corpora and their licence") func attribution() throws {
        let text = try String(contentsOf: Self.smoke.appendingPathComponent("ATTRIBUTION.md"), encoding: .utf8)
        for needle in ["speechocean762", "VCTK", "CC BY 4.0", "openslr.org/101", "datashare.ed.ac.uk"] {
            #expect(text.contains(needle), "\(needle)")
        }
    }

    @Test("eval-speakers.json: 18 tuning, 12 held-out, none bundled, p280 or p315") func evalSpeakers() throws {
        let manifest = try VCTKEvalSpeakersManifest.load(Repo.url("fixtures/vctk/eval-speakers.json"))
        #expect(manifest.tuningSpeakers.count == 18 && manifest.heldOutSpeakers.count == 12)
        let picked = Set(manifest.speakers.map(\.speaker))
        #expect(picked.count == 30)
        #expect(picked.isDisjoint(with: VCTK.bundledVoices + VCTK.excludedSpeakers))
        #expect(manifest.phrases == VCTK.phrases)
        #expect(manifest.speakers.allSatisfy { $0.files.count == 20 })
        let split = try JSONDecoder().decode(VCTKSplitManifest.self, from: Data(contentsOf: Repo.url("fixtures/splits/vctk.json")))
        let hash = SHA256Digest.hex(of: try Data(contentsOf: Repo.url("fixtures/vctk/eval-speakers.json")))
        let rebuilt = VCTKSplitManifest(evalSpeakers: manifest, evalSpeakersSHA256: hash, foldSeed: split.foldSeed, bootstrapSeed: split.bootstrapSeed)
        #expect(rebuilt == split)
    }

    @Test("One VCTK archive pin: spec 03's digest file and spec 02's pin hold the same SHA-256") func vctkArchivePinsAgree() throws {
        let line = try String(contentsOf: Repo.url("fixtures/vctk/vctk-0.92-archive.sha256"), encoding: .utf8)
        let digest = try #require(line.split(whereSeparator: \.isWhitespace).first.map(String.init))
        #expect(digest.count == 64)
        #expect(digest == (try Repo.pin("vctk", "archiveSHA256")))
    }
}
