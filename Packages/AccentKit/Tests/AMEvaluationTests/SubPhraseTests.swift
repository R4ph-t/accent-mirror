import Foundation
import Testing
import AMCore
import AMEvaluation

/// Spec 24: VCTK prompts 021 and 023 split into text-defined sub-phrases, cut at MFA word boundaries.
@Suite("VCTK sub-phrases") struct SubPhraseTests {
    static func table() throws -> VCTKSubPhraseTable {
        try VCTKSubPhraseTable.load(Repo.url("fixtures/vctk/sub-phrases.json"))
    }

    static func manifest() throws -> VCTKEvalSpeakersManifest {
        try VCTKEvalSpeakersManifest.load(Repo.url("fixtures/vctk/eval-speakers.json"))
    }

    static func cuts() throws -> VCTKSubPhraseCutList {
        try VCTKSubPhraseCutList.load(Repo.url("fixtures/vctk/sub-phrase-cuts.json"))
    }

    /// A word-level alignment of `text` starting at `offset` seconds, 0.3 s a word.
    static func alignment(_ text: String, offset: Double = 0.5) -> [VCTKTimedWord] {
        text.split(separator: " ").enumerated().map { i, word in
            VCTKTimedWord(word: String(word), start: offset + 0.3 * Double(i), end: offset + 0.3 * Double(i + 1))
        }
    }

    // MARK: - The table

    @Test("Every sub-phrase in sub-phrases.json is a contiguous word range ending at a sentence or clause boundary")
    func committedTableIsValid() throws {
        let table = try Self.table()
        let manifest = try Self.manifest()
        #expect(table.problems(phraseText: try #require(manifest.phraseText)).isEmpty)
        #expect(table.splitPrompts == ["021", "023"])
        #expect(table.subPhrases.map(\.id) == ["021-a", "021-b", "023-a", "023-b", "023-c"])
        // The sub-phrases of a prompt tile it: contiguous, in order, nothing dropped.
        for prompt in table.splitPrompts {
            let subs = table.subPhrases.filter { $0.prompt == prompt }
            let words = VCTKText.words(try #require(manifest.phraseText?[prompt]))
            #expect(subs.first?.firstWord == 0 && subs.last?.lastWord == words.count - 1)
            for (a, b) in zip(subs, subs.dropFirst()) { #expect(b.firstWord == a.lastWord + 1) }
            #expect(subs.map(\.text).joined(separator: " ") == words.joined(separator: " "))
        }
    }

    @Test("A range that ends mid-clause, or whose text isn't its words, is rejected") func badTablesAreCaught() throws {
        let table = try Self.table()
        let phraseText = try #require(try Self.manifest().phraseText)
        func with(_ sub: VCTKSubPhrase) -> VCTKSubPhraseTable {
            VCTKSubPhraseTable(rule: table.rule, prompts: table.prompts, subPhrases: [sub])
        }
        // 021-a ending at "size" (word 9): not a boundary.
        let midClause = VCTKSubPhrase(
            id: "021-a", prompt: "021", firstWord: 0, lastWord: 9,
            text: "the difference in the rainbow depends considerably upon the size", boundary: "clause")
        #expect(with(midClause).problems(phraseText: phraseText) == ["021-a: does not end at a sentence or clause boundary"])
        let wrongText = VCTKSubPhrase(
            id: "021-a", prompt: "021", firstWord: 0, lastWord: 12, text: "the difference in the rainbow", boundary: "clause")
        #expect(with(wrongText).problems(phraseText: phraseText) == ["021-a: text is not words 0...12 of 021"])
        let lateStart = VCTKSubPhrase(
            id: "021-a", prompt: "021", firstWord: 2, lastWord: 12,
            text: "in the rainbow depends considerably upon the size of the drops", boundary: "clause")
        #expect(with(lateStart).problems(phraseText: phraseText) == ["021-a: does not start at a sentence or clause boundary"])
    }

    @Test("Split prompts leave the positive set; their sub-phrases replace them") func evaluationPhrases() throws {
        let phrases = try Self.table().evaluationPhrases
        #expect(phrases.count == 24 - 2 + 5)
        #expect(!phrases.contains("021") && !phrases.contains("023"))
        #expect(phrases.contains("021-a") && phrases.contains("023-c"))
        #expect(Set(phrases.map(VCTK.sourcePrompt(of:))).count == 24)
        #expect(VCTK.headlineReference(for: "021-a") == "p225")
        #expect(VCTK.sourcePrompt(of: "015") == "015" && VCTK.sourcePrompt(of: "023-b") == "023")
    }

    // MARK: - The cuts

    @Test("One cut table applies to every speaker: the same words, wherever they fall in each clip")
    func oneTableForEverySpeaker() throws {
        let sub = try #require(try Self.table().subPhrases.first { $0.id == "023-b" })
        let manifest = try Self.manifest()
        let prompt = try #require(manifest.phraseText?["023"])
        let fast = VCTKSubPhraseCut.make(sub, transcript: prompt, alignment: Self.alignment(prompt, offset: 0.2))
        let slow = VCTKSubPhraseCut.make(sub, transcript: prompt, alignment: Self.alignment(prompt, offset: 1.7))
        let words = sub.text.split(separator: " ").map(String.init)
        // Words 14–26 of the prompt: 0.3 s each after the offset. The words touch their neighbours (no gap), so the
        // cut doesn't extend.
        for (cut, offset) in [(fast, 0.2), (slow, 1.7)] {
            guard case .cut(let start, let end, let wordStart, let wordEnd, let cutWords) = cut else {
                Issue.record("not cut: \(cut)")
                continue
            }
            #expect(abs(wordStart - (offset + 0.3 * 14)) < 1e-9 && abs(wordEnd - (offset + 0.3 * 27)) < 1e-9)
            #expect(abs(start - wordStart) < 0.0005 && abs(end - wordEnd) < 0.0005)
            #expect(cutWords == words)
        }
    }

    @Test("A cut extends into the gap before and after, stopping at the gap's midpoint")
    func extensionStopsAtGapMidpoint() {
        // 120 ms of silence before the first word and 400 ms after the last: the pre-roll stops at 60 ms, the tail
        // at 200 ms, so the cut never reaches the neighbouring word.
        let cut = VCTKSubPhraseCut.extend(wordStart: 2.0, wordEnd: 4.0, previousEnd: 1.88, nextStart: 4.4)
        #expect(cut.start == 1.94 && cut.end == 4.2)
        // Neighbours that touch the words: no extension at all.
        let touching = VCTKSubPhraseCut.extend(wordStart: 2.0, wordEnd: 4.0, previousEnd: 2.0, nextStart: 4.0)
        #expect(touching.start == 2.0 && touching.end == 4.0)
    }

    @Test("A cut gets the trim's full 200 ms pre-roll and 300 ms tail when the gap is wide, or at the clip edge")
    func fullExtension() throws {
        #expect(VCTKSubPhraseCut.preRoll == 0.2 && VCTKSubPhraseCut.tail == 0.3)
        let wide = VCTKSubPhraseCut.extend(wordStart: 2.0, wordEnd: 4.0, previousEnd: 1.0, nextStart: 5.0)
        #expect(wide.start == 1.8 && wide.end == 4.3)
        // No neighbouring word: the clip edge bounds it (0 at the start; the end is clamped to the audio on reading).
        let edges = VCTKSubPhraseCut.extend(wordStart: 0.1, wordEnd: 4.0, previousEnd: nil, nextStart: nil)
        #expect(edges.start == 0 && edges.end == 4.3)
        // Through make: 023-a starts the prompt and 023-c ends it, with silence around the words.
        let table = try Self.table()
        let prompt = try #require(try Self.manifest().phraseText?["023"])
        let alignment = Self.alignment(prompt, offset: 0.5)
        let first = try #require(table.subPhrases.first { $0.id == "023-a" })
        let last = try #require(table.subPhrases.first { $0.id == "023-c" })
        guard case .cut(let start, _, let wordStart, _, _) = VCTKSubPhraseCut.make(first, transcript: prompt, alignment: alignment),
              case .cut(_, let end, _, let wordEnd, _) = VCTKSubPhraseCut.make(last, transcript: prompt, alignment: alignment)
        else { Issue.record("not cut"); return }
        #expect(wordStart == 0.5 && start == 0.3)
        #expect(abs(end - (wordEnd + 0.3)) < 0.0005)
    }

    @Test("The committed cut list: from this table, every listed clip once per sub-phrase, cut at exactly its words")
    func committedCutList() throws {
        let table = try Self.table()
        let manifest = try Self.manifest()
        let cuts = try Self.cuts()
        #expect(cuts.subPhrasesSHA256 == SHA256Digest.hex(of: try Data(contentsOf: Repo.url("fixtures/vctk/sub-phrases.json"))))
        #expect(cuts.aligner["version"] == "3.4.4" && cuts.aligner["acousticModel"] == "english_mfa.zip")
        let subs = Dictionary(uniqueKeysWithValues: table.subPhrases.map { ($0.id, $0) })
        for sub in table.subPhrases {
            let listed = (manifest.bundled + manifest.speakers).filter { $0.files[sub.prompt] != nil }.map(\.speaker)
            #expect(cuts.entries.filter { $0.subPhrase == sub.id }.map(\.speaker).sorted() == listed.sorted(), "\(sub.id)")
        }
        #expect(cuts.entries.count == Set(cuts.entries.map { "\($0.speaker)_\($0.subPhrase)" }).count)
        for entry in cuts.entries {
            let sub = try #require(subs[entry.subPhrase])
            switch entry.outcome {
            case .cut(let start, let end, let wordStart, let wordEnd, let words):
                let clip = "\(entry.speaker)_\(entry.subPhrase)"
                #expect(words.joined(separator: " ") == sub.text, "\(clip)")
                #expect(0 <= start && start <= wordStart && wordStart < wordEnd && wordEnd <= end, "\(clip)")
                // Extended into the silence by at most the trim's pre-roll and tail.
                #expect(wordStart - start <= 0.2005 && end - wordEnd <= 0.3005, "\(clip)")
            case .mfaMismatch, .noAlignment, .transcriptMismatch:
                break  // Rejected and counted by vctk-trim; never cut.
            }
        }
        // Sub-phrases of one clip never overlap and follow the text's order.
        for speaker in Set(cuts.entries.map(\.speaker)) {
            for prompt in table.splitPrompts {
                let spans = cuts.entries.filter { $0.speaker == speaker && VCTK.sourcePrompt(of: $0.subPhrase) == prompt }
                    .sorted { $0.subPhrase < $1.subPhrase }
                    .compactMap { entry -> (Double, Double)? in
                        if case .cut(let s, let e, _, _, _) = entry.outcome { return (s, e) } else { return nil }
                    }
                for (a, b) in zip(spans, spans.dropFirst()) { #expect(a.1 <= b.0, "\(speaker) \(prompt)") }
            }
        }
    }

    @Test("A clip whose MFA words don't match is rejected, never guessed") func mfaMismatchIsRejected() throws {
        let sub = try #require(try Self.table().subPhrases.first { $0.id == "021-b" })
        let prompt = try #require(try Self.manifest().phraseText?["021"])
        // MFA dropped "colored".
        let dropped = Self.alignment(prompt.replacingOccurrences(of: "colored ", with: ""))
        #expect(VCTKSubPhraseCut.make(sub, transcript: prompt, alignment: dropped)
            == .mfaMismatch(words: VCTKText.words(prompt).filter { $0 != "colored" }))
        // An unknown word: MFA's <unk> never matches.
        let unknown = Self.alignment(prompt.replacingOccurrences(of: "width", with: "<unk>"))
        guard case .mfaMismatch = VCTKSubPhraseCut.make(sub, transcript: prompt, alignment: unknown) else {
            Issue.record("an <unk> word was cut")
            return
        }
        // No alignment at all.
        #expect(VCTKSubPhraseCut.make(sub, transcript: prompt, alignment: nil) == .noAlignment)
        // The words appear twice: ambiguous, so rejected.
        let twice = Self.alignment(prompt + " " + sub.text)
        guard case .mfaMismatch = VCTKSubPhraseCut.make(sub, transcript: prompt, alignment: twice) else {
            Issue.record("an ambiguous match was cut")
            return
        }
        // A transcript that doesn't contain the sub-phrase: the clip is not listed.
        let other = prompt.replacingOccurrences(of: "size of the drops increases", with: "size of the drop increases")
        #expect(VCTKSubPhraseCut.make(sub, transcript: other, alignment: Self.alignment(prompt)) == .transcriptMismatch)
    }

    @Test("MFA-mismatch rejections are counted per sub-phrase, next to the trim's") func mismatchesAreCounted() throws {
        let manifest = try SyntheticVCTK.manifest()
        let phrases = try Self.table().evaluationPhrases
        let lines = VCTKPairs.rejectionsByPhrase(
            trimmed: [VCTKClip(speaker: "p429", phrase: "023-c")],
            misaligned: [VCTKClip(speaker: "p225", phrase: "021-b"), VCTKClip(speaker: "p420", phrase: "021-b")],
            phrases: phrases, manifest: manifest)
        #expect(lines == [
            "021-a: 0 rejected by the trim (0 held-out), 0 by MFA mismatch (0 held-out)",
            "021-b: 0 rejected by the trim (0 held-out), 2 by MFA mismatch (1 held-out), reference p225 rejected: phrase dropped",
            "023-a: 0 rejected by the trim (0 held-out), 0 by MFA mismatch (0 held-out)",
            "023-b: 0 rejected by the trim (0 held-out), 0 by MFA mismatch (0 held-out)",
            "023-c: 1 rejected by the trim (1 held-out), 0 by MFA mismatch (0 held-out)",
        ])
    }

    // MARK: - Counting

    /// Every clip of every evaluation phrase, for every bundled voice and eval speaker.
    static func clips(_ manifest: VCTKEvalSpeakersManifest, phrases: [String]) -> Set<VCTKClip> {
        Set((manifest.bundled + manifest.speakers).flatMap { e in phrases.map { VCTKClip(speaker: e.speaker, phrase: $0) } }
            .filter { !($0.speaker == "p225" && VCTK.sourcePrompt(of: $0.phrase) == "015") })
    }

    @Test("Phrases count sub-phrases; distinct source prompts are reported next to them") func phraseAndPromptCounts() throws {
        let manifest = try SyntheticVCTK.manifest()
        let phrases = try Self.table().evaluationPhrases
        var clips = Self.clips(manifest, phrases: phrases)
        // Today's shape: p225 loses nine whole prompts, so 13 survive, plus five sub-phrases.
        for phrase in ["001", "003", "008", "011", "016", "019", "022", "024", "002"] {
            clips.remove(VCTKClip(speaker: "p225", phrase: phrase))
        }
        let pairs = VCTKPairs(manifest: manifest, available: clips, phrases: phrases)
        #expect(pairs.phraseCount == 13 + 5 && pairs.sourcePromptCount == 13 + 2)
        #expect(pairs.shortfalls().isEmpty && pairs.status() == .evaluable)
        #expect(pairs.minimums().map(\.line) == [
            "pairs 216 (≥ 150): PASS", "phrases 18 (≥ 18): PASS", "held-out speakers 12 (≥ 12): PASS",
        ])
    }

    @Test("Still short with sub-phrases: NOT EVALUATED, never a pass, with the source-prompt count")
    func stillShortNeverPasses() throws {
        let manifest = try SyntheticVCTK.manifest()
        let phrases = try Self.table().evaluationPhrases
        var clips = Self.clips(manifest, phrases: phrases)
        for phrase in ["001", "002", "003", "004", "005", "006", "007", "008", "009", "010", "023-a"] {
            clips.remove(VCTKClip(speaker: "p225", phrase: phrase))
        }
        let pairs = VCTKPairs(manifest: manifest, available: clips, phrases: phrases)
        #expect(pairs.phraseCount == 16 && pairs.sourcePromptCount == 14)
        let shortfall = "phrases 16 < 18 (14 distinct source prompts)"
        #expect(pairs.shortfalls() == [shortfall])
        #expect(pairs.minimums().map(\.line).contains("phrases 16 (≥ 18): NOT EVALUATED"))
        let status = pairs.status()
        #expect(status == .notEvaluated(shortfalls: [shortfall], blockedOn: "spec 24"))
        let passing = Dictionary(uniqueKeysWithValues: PositiveSetGates.dependents().map {
            ($0.name, MetricResult(name: $0.name, layer: .shippedConfigCheck, n: 200, value: 0, gate: $0.gate, status: .pass))
        })
        for line in PositiveSetGates.lines(positiveSet: status, measured: passing, pairs: pairs.headline.count) {
            #expect(!line.status.isPass && line.status.text.hasPrefix("NOT EVALUATED"), "\(line.name)")
        }
        #expect(!ReleaseSummary(negativeSet: .pass, positiveSet: status, gated: []).releaseGateMet)
    }

    // MARK: - Bootstrap

    @Test("The two-way bootstrap clusters sub-phrases by source prompt; worst phrase stays per sub-phrase")
    func bootstrapClustersBySourcePrompt() throws {
        // Every speaker hits 021-a and misses 021-b. Drawn as one prompt, each resample weights them equally, so the
        // mean is always 0.5; drawn as two phrases, the interval spreads.
        let pairs = (0..<12).flatMap { s in
            ["021-a", "021-b"].map { VCTKPair(speaker: "p\(400 + s)", phrase: $0, reference: "p225") }
        }
        let units = pairs.map { $0.scoredUnit(hit: $0.phrase == "021-a") }
        let boot = { (units: [ScoredUnit]) in
            ClusteredBootstrap.meanInterval(
                units: units.map {
                    BootstrapUnit(speaker: $0.speaker, phrase: $0.phrase, phraseCluster: $0.phraseCluster, value: $0.hit ? 1 : 0)
                },
                clustering: .speakersAndPhrases, resamples: 500, seed: 11)
        }
        let clustered = boot(units)
        #expect(clustered.lower == 0.5 && clustered.upper == 0.5)
        let independent = boot(units.map { ScoredUnit(speaker: $0.speaker, phrase: $0.phrase, hit: $0.hit) })
        #expect(independent.lower < 0.5 && independent.upper > 0.5)

        let metric = MetricResult.rate(
            name: "hit rate", layer: .shippedConfigCheck, units: units, gate: nil, minimumN: 1,
            bootstrap: (.speakersAndPhrases, 500, 11), reportWorstPhrase: true)
        #expect(metric.intervals.last == clustered)
        // Worst phrase is per sub-phrase, not per prompt (no gate: the highest rate is the worst).
        #expect(metric.worstPhrase?.id == "021-a")
    }
}
