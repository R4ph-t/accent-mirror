@testable import AMJudging
import AMCore
import Foundation
import Testing

@Suite("Units, lenient classes and scoring") struct ScorerTests {
    let vocab = TokenVocabulary.lv60Espeak

    func tokens(_ unit: JudgingUnit) -> [[String]] {
        let names = vocab.tokensByID
        return unit.acceptable.map { $0.map { names[$0] ?? "?" } }
    }

    func units(_ word: String, _ phones: String) throws -> [JudgingUnit] {
        try #require(UnitBuilder.units(word: word, phones: phones.split(separator: " ").map(String.init),
                                       vocabulary: vocab))
    }

    @Test("lenient classes: T accepts flap and glottal stop, unstressed AH accepts the reduced vowels")
    func lenientClasses() throws {
        let butter = try units("butter", "B AH1 T ER0")
        #expect(butter.count == 4)
        #expect(tokens(butter[1]) == [["ʌ"], ["ə"], ["ɐ"]])
        #expect(tokens(butter[2]) == [["t"], ["ɾ"], ["ʔ"]])
        #expect(tokens(butter[3]) == [["ɚ"], ["ə"]])
        let about = try units("about", "AH0 B AW1 T")
        #expect(tokens(about[0]) == [["ə"], ["ɐ"], ["ᵻ"], ["ɪ"], ["ʌ"]])
        #expect(tokens(about[3]) == [["t"], ["ɾ"], ["ʔ"], []], "word-final T may drop")
    }

    @Test("composites: vowel+R merges, but not before a vowel; AH0+L merges")
    func composites() throws {
        let store = try units("store", "S T AO1 R")
        #expect(store.count == 3 && store[2].members == [2, 3])
        #expect(tokens(store[2]) == [["ɔːɹ"], ["oːɹ"], ["ɔː", "ɹ"], ["ɔ", "ɹ"]])
        let story = try units("story", "S T AO1 R IY0")
        #expect(story.count == 5, "intervocalic R stays its own unit")
        let miracle = try units("miracle", "M IH1 R AH0 K AH0 L")
        #expect(miracle.last?.members == [5, 6])
        #expect(tokens(miracle.last!) == [["əl"], ["ə", "l"], ["l"], ["ɪ", "l"]])
        let fire = try units("fire", "F AY1 ER0")
        #expect(fire.count == 2 && tokens(fire[1]).first == ["aɪɚ"])
    }

    @Test("weak forms and secondary stress")
    func weakForms() throws {
        #expect(tokens(try units("have", "HH AE1 V")[0]).last == [])
        #expect(tokens(try units("of", "AH1 V")[1]).last == [])
        #expect(tokens(try units("and", "AH0 N D")[1]).last == [])
        #expect(!tokens(try units("hat", "HH AE1 T")[0]).contains([]), "only function words drop HH")
        #expect(!tokens(try units("t", "T")[0]).contains([]), "a word's only phone never drops")
        let photo = try units("photograph", "F OW1 T AH0 G R AE2 F")
        #expect(tokens(photo[6]).suffix(2) == [["ə"], ["ɪ"]])
    }

    @Test("an unknown phone leaves the word unjudged") func unknownPhone() {
        #expect(UnitBuilder.units(word: "x", phones: ["QQ1"], vocabulary: vocab) == nil)
    }

    @Test("display phones keep AH0 apart and strip every other stress digit")
    func displayPhones() {
        let shown: [String] = ["AH0", "AH1", "AH2", "IH0", "ER0", "T"].map { SoundScorer.displayPhone($0) }
        #expect(shown == ["AH0", "AH", "AH", "IH", "ER", "T"])
    }

    @Test("shared prefix/suffix GOP terms equal the full CTC forward pass", arguments: ParityFixture.names.prefix(3))
    func sharedLatticeEqualsFull(name: String) throws {
        let fixture = try ParityFixture.load(name)
        let e = Emissions(try fixture.posteriors(), blank: 0)
        let units = fixture.expectedWords.enumerated().flatMap { w, word in
            UnitBuilder.units(word: word.text, phones: word.variants[fixture.chosenVariant[w]], vocabulary: vocab) ?? []
        }
        let blank = e.column(0)
        let canonical = units.flatMap(\.canonical)
        let lattice = CTCLattice(labels: canonical, emissions: e, blankColumn: blank)
        #expect(abs(lattice.logLikelihood - CTC.logLikelihood(canonical, emissions: e, blankColumn: blank)) < 1e-9)
        var columns: [Int: [Double]] = [:]
        for id in vocab.englishIDs { columns[id] = e.column(id) }
        let shared = GOP.Shared(lattice: lattice, blankColumn: blank, columns: columns, canonical: canonical)
        var start = 0
        var worst = 0.0
        for unit in units {
            let range = start..<(start + unit.canonical.count)
            for middle in unit.acceptable + [[], [vocab.ids["s"]!], [vocab.ids["s"]!, vocab.ids["s"]!]] {
                let prefix: [Int] = Array(canonical[..<range.lowerBound])
                let suffix: [Int] = Array(canonical[range.upperBound...])
                let full = CTC.logLikelihood(prefix + middle + suffix, emissions: e, blankColumn: blank)
                let fast = shared.logLikelihood(replacing: range, with: middle)
                if full == -.infinity { #expect(fast == -.infinity) } else { worst = max(worst, abs(full - fast)) }
            }
            start += unit.canonical.count
        }
        #expect(worst < 1e-6, "worst difference \(worst)")
    }

    @Test("out-of-vocabulary words stay unjudged; the rest are judged; a word is flagged iff a phone is")
    func oovAndFlags() throws {
        let fixture = try ParityFixture.load("p225_013")
        var words = fixture.expectedWords
        words.insert(ExpectedWord(index: WordIndex(99), text: "zyzzyva", variants: []), at: 2)
        let judged = SoundScorer.judge(try fixture.posteriors(), words: words)
        #expect(judged.count == words.count)
        #expect(judged[2].state == .unjudged(.notInDictionary) && judged[2].youRange == nil && !judged[2].flagged)
        #expect(judged.enumerated().allSatisfy { $0.offset == 2 || !$0.element.phones.isEmpty })
        #expect(judged.map(\.index) == words.map(\.index))
        for word in judged { #expect(word.flagged == word.phones.contains(where: \.flagged)) }
        for phone in judged.flatMap(\.phones) {
            #expect(phone.gop <= 0 && (0...1).contains(phone.confidence))
            #expect(phone.flagged == (1 - phone.confidence > 0.22))
        }
    }

    @Test("every word out of vocabulary: every word unjudged") func allOOV() throws {
        let posteriors = try ParityFixture.load("p225_013").posteriors()
        let judged = SoundScorer.judge(posteriors, words: [ExpectedWord(index: WordIndex(0), text: "qx", variants: [])])
        #expect(judged.map(\.state) == [.unjudged(.notInDictionary)])
    }

    @Test("the frozen threshold is the spike's") func threshold() {
        #expect(Thresholds.current.soundJudging.errorThreshold == 0.22)
    }

    @Test("bucket choice and normalisation") func buckets() throws {
        let json = """
        {"formatVersion":1,"model":"wav2vec2-lv-60-espeak-cv-ft","source":{"repo":"r","commit":"abc","license":"Apache-2.0"},
         "conversion":{"inputBucketsSeconds":[2,4,6,8,10,12,15]},"packageSHA256":"0123456789abcdef","compiled":"LV60Int8.mlmodelc",
         "input":"audio","output":"logprobs","vocabulary":["<pad>"],"blank":"<pad>","sampleRate":16000,"samplesPerFrame":320}
        """
        let manifest = try JSONDecoder().decode(SoundJudgeModelManifest.self, from: Data(json.utf8))
        #expect(manifest.modelID == "wav2vec2-lv-60-espeak-cv-ft@abc#01234567")
        #expect(manifest.bucketSamples(for: 1600) == 32_000)
        #expect(manifest.bucketSamples(for: 64_000) == 64_000)
        #expect(manifest.bucketSamples(for: 64_001) == 96_000)
        #expect(manifest.bucketSamples(for: 240_001) == nil)
        #expect(TokenVocabulary(tokens: manifest.vocabulary, blank: "<pad>") == nil, "English tokens missing")
        let x = SoundJudge.modelInput([1, -1, 1, -1], bucket: 8)
        let total: Float = x.reduce(0, +)
        #expect(x.count == 8 && abs(total) < 1e-5)
        let power: Float = x.map { $0 * $0 }.reduce(0, +) / 8
        #expect(abs(power - 1) < 1e-3)
    }

    @Test("a missing model folder is modelNotInstalled") func missingFolder() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "no-such-judge-\(UUID().uuidString)")
        await #expect(throws: SoundJudgeError.modelNotInstalled) { _ = try await SoundJudge.load(folder: folder) }
    }
}
