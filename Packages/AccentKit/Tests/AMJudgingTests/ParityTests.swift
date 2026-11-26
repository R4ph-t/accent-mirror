@testable import AMJudging
import AMCore
import Foundation
import Testing

/// A parity fixture made by `tools/make_judge_fixtures.py` from the judging spike's Python reference.
struct ParityFixture: Decodable {
    struct Column: Decodable {
        let token: String
        let id: Int
    }

    struct Word: Decodable {
        let text: String
        let variants: [String]
    }

    struct Heard: Decodable, Equatable {
        let sound: String?
        let nothing: Bool?
    }

    struct Unit: Decodable {
        let word: Int
        let members: [Int]
        let phones: [String]
        let gop: Double
        let pError: Double
        let flagged: Bool
        let heardInstead: Heard?
        let frames: [Int]
    }

    let id: String
    let text: String
    let frames: Int
    let vocabularySize: Int
    let columns: [Column]
    let posteriorsFloat16Base64: String
    let words: [Word]
    let chosenVariant: [Int]
    let units: [Unit]
    let takeSeconds: Double

    /// The P(error) threshold the fixtures' `flagged` were computed at.
    static let threshold = 0.22

    static let names = ["p225_013", "p233_013", "p252_006", "p225_002", "p233_012", "0044_0056"]

    static func load(_ name: String) throws -> ParityFixture {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(ParityFixture.self, from: Data(contentsOf: url))
    }

    /// The full posteriors: the stored columns, every other column −1e4.
    func posteriors() throws -> LogPosteriors {
        let bytes = try #require(Data(base64Encoded: posteriorsFloat16Base64))
        let halves = bytes.withUnsafeBytes { raw in
            (0..<(bytes.count / 2)).map { raw.loadUnaligned(fromByteOffset: 2 * $0, as: UInt16.self).littleEndian }
        }
        #expect(halves.count == frames * columns.count)
        var values = [Float](repeating: -1e4, count: frames * vocabularySize)
        for t in 0..<frames {
            for (c, column) in columns.enumerated() {
                values[t * vocabularySize + column.id] = Self.float(halfBits: halves[t * columns.count + c])
            }
        }
        return LogPosteriors(frames: frames, vocabularySize: vocabularySize, values: values)
    }

    /// IEEE half -> Float, without relying on `Float16` (unavailable on some hosts).
    static func float(halfBits h: UInt16) -> Float {
        let sign: UInt32 = UInt32(h & 0x8000) << 16
        let exponent = Int((h >> 10) & 0x1F)
        let mantissa = UInt32(h & 0x3FF)
        if exponent == 0 {
            let magnitude = Float(mantissa) * Float(sign == 0 ? 1 : -1) * pow(2, -24)
            return magnitude
        }
        if exponent == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13)) }
        return Float(bitPattern: sign | UInt32(exponent - 15 + 127) << 23 | (mantissa << 13))
    }

    var expectedWords: [ExpectedWord] {
        words.enumerated().map { i, word in
            ExpectedWord(index: WordIndex(i), text: word.text,
                         variants: word.variants.map { $0.split(separator: " ").map(String.init) })
        }
    }
}

@Suite("Parity with the judging spike") struct ParityTests {
    @Test("the built-in lv-60 token table matches the model vocabulary's ids")
    func vocabularyTable() throws {
        let fixture = try ParityFixture.load("p225_013")
        #expect(fixture.columns.first?.id == 0 && fixture.columns.first?.token == "<pad>")
        let table = Dictionary(uniqueKeysWithValues: fixture.columns.dropFirst().map { ($0.token, $0.id) })
        #expect(table == TokenVocabulary.lv60Espeak.ids)
        #expect(Set(table.keys) == Lexicon.englishTokens)
    }

    @Test("GOP, flags, competitors, variants and alignment match the Python reference", arguments: ParityFixture.names)
    func matchesReference(name: String) throws {
        let fixture = try ParityFixture.load(name)
        let posteriors = try fixture.posteriors()
        // The fixtures' flags were computed at 0.22 (tools/make_judge_fixtures.py), so parity checks the scorer at
        // that threshold; the live threshold is checked in ScorerTests.
        let judged = SoundScorer.judge(posteriors, words: fixture.expectedWords, vocabulary: .lv60Espeak,
                                       takeSeconds: fixture.takeSeconds, errorThreshold: ParityFixture.threshold)
        #expect(judged.count == fixture.words.count)
        for (w, word) in judged.enumerated() {
            let chosen = fixture.expectedWords[w].variants[fixture.chosenVariant[w]]
            #expect(word.phones.map(\.phone) == chosen.map(SoundScorer.displayPhone), "\(name) word \(w) variant")
        }
        var flags = 0
        for unit in fixture.units {
            let phones = judged[unit.word].phones
            let start = Double(unit.frames[0]) * 0.02
            let end = min(Double(unit.frames[1] + 1) * 0.02, fixture.takeSeconds)
            for member in unit.members {
                let phone = phones[member]
                let label = "\(name) word \(unit.word) \(unit.phones)"
                #expect(abs(phone.gop - unit.gop) <= 1e-3, "\(label): GOP \(phone.gop) vs \(unit.gop)")
                #expect(abs((1 - phone.confidence) - unit.pError) <= 1e-3, "\(label): P(error)")
                #expect(phone.flagged == unit.flagged, "\(label): flag")
                let heard: ParityFixture.Heard? = switch phone.heardInstead {
                case .sound(let token): .init(sound: token, nothing: nil)
                case .nothing: .init(sound: nil, nothing: true)
                case nil: nil
                }
                #expect(heard == unit.heardInstead, "\(label): heard instead")
                #expect(phone.youRange.map { abs($0.start - start) < 1e-9 && abs($0.end - end) < 1e-9 } == true,
                        "\(label): range \(String(describing: phone.youRange)) vs \(start)–\(end)")
            }
            flags += unit.flagged ? 1 : 0
        }
        for word in judged {
            #expect(word.flagged == word.phones.contains(where: \.flagged))
            if let range = word.youRange {
                #expect(word.phones.allSatisfy { $0.youRange.map { range.start <= $0.start && $0.end <= range.end } ?? false })
            }
        }
        // The set covers flags, composites and weak forms (checked once, over the clips that carry them).
        if name == "p225_013" {
            #expect(flags >= 1)
            #expect(fixture.units.contains { $0.members.count == 2 })
            #expect(fixture.units.contains { $0.flagged && $0.phones == ["HH"] }, "weak-form 'have' flagged")
        }
    }

    @Test("the fixtures carry at least one flag, one composite and one speechocean762 error")
    func coverage() throws {
        let all = try ParityFixture.names.map(ParityFixture.load)
        #expect(all.contains { $0.units.contains(where: \.flagged) })
        #expect(all.contains { $0.units.contains { $0.members.count == 2 } })
        #expect(all.contains { $0.id == "0044_0056" && $0.units.contains(where: \.flagged) })
    }
}
