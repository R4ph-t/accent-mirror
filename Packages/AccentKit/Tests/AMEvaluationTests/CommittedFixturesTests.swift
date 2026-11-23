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

    @Test("eval-speakers.json: recorded counts match the listed speakers and meet the floors (≥ 18 / ≥ 12)")
    func evalSpeakers() throws {
        let manifest = try VCTKEvalSpeakersManifest.load(Repo.url("fixtures/vctk/eval-speakers.json"))
        #expect(manifest.tuningCount == manifest.tuningSpeakers.count)
        #expect(manifest.heldOutCount == manifest.heldOutSpeakers.count)
        #expect(manifest.tuningCount >= VCTKEvalSpeakersManifest.minimumTuningSpeakers)
        #expect(manifest.heldOutCount >= VCTKEvalSpeakersManifest.minimumHeldOutSpeakers())
        #expect(manifest.meetsFloors())
        // Today's recorded counts (CTO ruling): 24 / 16.
        #expect(manifest.tuningCount == 24 && manifest.heldOutCount == 16)
        let picked = Set(manifest.speakers.map(\.speaker))
        #expect(picked.count == manifest.tuningCount + manifest.heldOutCount)
        #expect(picked.isDisjoint(with: VCTK.bundledVoices + VCTK.excludedSpeakers))
        #expect(manifest.phrases == VCTK.phrases && VCTK.phrases.count == 24)
        // Every eval speaker has all of CPO's 20; an added prompt is listed only where its transcript matched.
        #expect(manifest.speakers.allSatisfy { Set(VCTK.starterPhrases).isSubset(of: $0.files.keys) })
        #expect((manifest.bundled + manifest.speakers).allSatisfy { Set($0.files.keys).isSubset(of: VCTK.phrases) })
        let split = try JSONDecoder().decode(VCTKSplitManifest.self, from: Data(contentsOf: Repo.url("fixtures/splits/vctk.json")))
        let hash = SHA256Digest.hex(of: try Data(contentsOf: Repo.url("fixtures/vctk/eval-speakers.json")))
        let rebuilt = VCTKSplitManifest(evalSpeakers: manifest, evalSpeakersSHA256: hash, foldSeed: split.foldSeed, bootstrapSeed: split.bootstrapSeed)
        #expect(rebuilt == split)
    }

    /// The 30 speakers of the first build, in pick order, with their split. The CTO ruling adds speakers inside the
    /// existing split: none of these may move across the tuning / held-out line or leave the manifest.
    static let originalSpeakers: [(String, VCTKSplit)] = [
        ("p374", .tuning), ("p262", .heldOut), ("p248", .tuning), ("s5", .heldOut), ("p347", .tuning),
        ("p363", .tuning), ("p238", .heldOut), ("p245", .tuning), ("p301", .heldOut), ("p256", .tuning),
        ("p326", .tuning), ("p271", .heldOut), ("p251", .tuning), ("p323", .heldOut), ("p317", .tuning),
        ("p261", .tuning), ("p266", .heldOut), ("p334", .tuning), ("p239", .heldOut), ("p285", .tuning),
        ("p376", .tuning), ("p314", .heldOut), ("p303", .tuning), ("p304", .heldOut), ("p288", .tuning),
        ("p360", .tuning), ("p269", .heldOut), ("p246", .tuning), ("p336", .heldOut), ("p351", .tuning),
    ]

    @Test("Added speakers: the first 30 picks keep their order and split; the new 10 follow the same 3-of-5 rule")
    func addedSpeakersKeepSplit() throws {
        let manifest = try VCTKEvalSpeakersManifest.load(Repo.url("fixtures/vctk/eval-speakers.json"))
        let speakers = manifest.speakers.map { ($0.speaker, $0.split) }
        #expect(speakers.count == 40)
        #expect(speakers.prefix(30).map(\.0) == Self.originalSpeakers.map(\.0))
        #expect(speakers.prefix(30).map(\.1) == Self.originalSpeakers.map { Optional($0.1) })
        let pattern: [VCTKSplit] = [.tuning, .heldOut, .tuning, .heldOut, .tuning]
        #expect(speakers.enumerated().allSatisfy { $0.element.1 == pattern[$0.offset % 5] })
    }

    @Test("One VCTK archive pin: spec 03's digest file and spec 02's pin hold the same SHA-256") func vctkArchivePinsAgree() throws {
        let line = try String(contentsOf: Repo.url("fixtures/vctk/vctk-0.92-archive.sha256"), encoding: .utf8)
        let digest = try #require(line.split(whereSeparator: \.isWhitespace).first.map(String.init))
        #expect(digest.count == 64)
        #expect(digest == (try Repo.pin("vctk", "archiveSHA256")))
    }
}
