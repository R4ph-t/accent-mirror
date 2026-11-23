import Foundation
import Testing
import AMCore
@testable import AMAlignment

@Suite("Equivalence table (plan §4.1)")
struct EquivalenceTableTests {
    @Test("Every row of every kind holds in both directions")
    func everyRowBothWays() throws {
        let table = try EquivalenceTable.bundled()
        for kind in EquivalenceRow.Kind.allCases {
            #expect(table.rows.contains { $0.kind == kind }, "no \(kind) rows")
        }
        var checked = 0
        for row in table.rows {
            let forms = row.forms.map { $0.joined(separator: " ") }
            for (a, b) in zip(forms, forms.dropFirst()) {
                #expect(table.areEquivalent(a, b), "\(row.kind): \(a) → \(b)")
                #expect(table.areEquivalent(b, a), "\(row.kind): \(b) → \(a)")
                checked += 1
            }
        }
        #expect(checked > 10_000)
    }

    @Test(
        "Named examples, both ways",
        arguments: [
            ("don't", "do not"), ("it's", "it is"), ("it's", "it has"), ("can't", "cannot"),
            ("1990", "nineteen ninety"), ("1905", "nineteen oh five"), ("21", "twenty-one"), ("21", "twenty one"),
            ("105", "one hundred and five"), ("2024", "two thousand twenty four"), ("2024", "twenty twenty-four"),
            ("9999", "nine thousand nine hundred and ninety-nine"), ("0", "zero"), ("1st", "first"),
            ("31st", "thirty-first"), ("train station", "train-station"), ("train station", "trainstation"),
            ("rainbow", "rain bow"), ("color", "colour"), ("theater", "theatre"), ("Organize", "organise"),
        ])
    func namedExamples(a: String, b: String) throws {
        let table = try EquivalenceTable.bundled()
        #expect(table.areEquivalent(a, b))
        #expect(table.areEquivalent(b, a))
    }

    @Test(
        "Anything else is not equivalent",
        arguments: [
            ("it is", "it has"),  // both are "it's", but not each other
            ("going to", "gonna"), ("10000", "ten thousand"), ("32nd", "thirty-second"), ("record", "records"),
            ("well-known", "well known"),  // a compound not on the list
            ("colour", "color red"),
        ])
    func notEquivalent(a: String, b: String) throws {
        let table = try EquivalenceTable.bundled()
        #expect(!table.areEquivalent(a, b))
        #expect(!table.areEquivalent(b, a))
    }

    @Test("No number form belongs to two different numbers")
    func numberFormsAreUnambiguous() {
        var owner: [[String]: Int] = [:]
        for (id, row) in NumberSpelling.rows().enumerated() {
            for form in row.forms {
                #expect(owner[form, default: id] == id, "\(form.joined(separator: " "))")
                owner[form] = id
            }
        }
    }
}

@Suite("Word alignment (plan §4.3)")
struct WordAlignerTests {
    let aligner: WordAligner

    init() throws { aligner = try .bundled() }

    func align(_ phrase: String, _ said: String, targets: Set<Int>? = nil) throws -> (String, AlignmentSummary) {
        let expected = try starterPhrase(phrase, targets: targets)
        let result = try aligner.align(expected, heard: try heard(said))
        return (render(result.alignment, expected), result.summary)
    }

    @Test(
        "Alignment table",
        arguments: [
            // phrase, heard, rendering
            ("the rainbow is bright", "the rainbow is bright", "the rainbow is bright"),
            ("the rainbow is bright", "the big rainbow is bright", "the +big rainbow is bright"),  // insertion
            ("the rainbow is bright", "the rainbow bright", "the rainbow -is bright"),  // omission
            ("the rainbow is bright", "the rainbow is white", "the rainbow is ~white(bright)"),  // substitution
            ("the rainbow is bright", "rainbow is bright today", "-the rainbow is bright +today"),
            ("the rainbow is bright", "", "-the -rainbow -is -bright"),
            ("", "hello there", "+hello +there"),
            // Normalisation: fillers, repeats, case and punctuation, contractions, numbers, compounds, US/UK.
            ("I want the red one", "um I I want uh the red one", "i want the red one"),
            ("They had had enough", "they had had enough", "they had had enough"),
            ("They had had enough", "they had had had enough", "they had had enough"),
            ("Don't stop, Stella!", "do not stop stella", "don't stop stella"),
            ("I do not know", "I don't know", "i do not know"),
            ("It is late", "it has late", "it ~has(is) late"),  // "it's" is both, but they aren't each other
            ("Born in 1990.", "born in nineteen ninety", "born in 1990"),
            ("the 21st time", "the twenty first time", "the 21st time"),
            ("meet at the train station", "meet at the train-station", "meet at the train station"),
            ("meet at the train station", "meet at the train stations", "meet at the train ~stations(station)"),
            ("a colourful rainbow", "a colorful rainbow", "a colourful rainbow"),
            ("a colourful rainbow", "a colorless rainbow", "a ~colorless(colourful) rainbow"),
        ])
    func table(phrase: String, said: String, expected: String) throws {
        #expect(try align(phrase, said).0 == expected)
    }

    @Test("Your-time order with phrase order preserved; insertions name the phrase word before them")
    func pairsShape() throws {
        let expected = try starterPhrase("the rainbow is bright")
        let result = try aligner.align(expected, heard: try heard("so the rainbow is very bright"))
        let alignment = result.alignment
        guard case .inserted(let first, _, let after) = alignment.pairs[0] else { Issue.record("no insertion"); return }
        #expect(first == "so" && after == nil)
        guard case .inserted(let very, _, let afterIs) = alignment.pairs[4] else { Issue.record("no insertion"); return }
        #expect(very == "very" && afterIs == WordIndex(2))
        let starts = alignment.pairs.compactMap(\.yourRange?.start)
        #expect(starts == starts.sorted())
    }

    @Test("A joined compound heard for two phrase words splits its time between them")
    func joinedCompoundSplitsTime() throws {
        let expected = try starterPhrase("train station")
        let said = [HeardWord(text: "trainstation", range: try TimeRange(start: 1.0, end: 2.2))]
        let pairs = try aligner.align(expected, heard: said).alignment.pairs
        // 5 letters to 7: "train" gets 5/12 of the 1.2 s.
        #expect(pairs.map(\.phraseWord) == [WordIndex(0), WordIndex(1)])
        let ranges = pairs.compactMap(\.yourRange)
        #expect(ranges.count == 2)
        #expect(ranges.first?.start == 1.0 && ranges.last?.end == 2.2)
        #expect(abs((ranges.first?.end ?? 0) - 1.5) < 1e-9)
        #expect(ranges.first?.end == ranges.last?.start)
        #expect(pairs.allSatisfy { if case .present = $0 { true } else { false } })
    }

    @Test("A missing target is listed, and the match % counts content words only")
    func missingTarget() throws {
        // Content words: rainbow, bright, sky. Target: rainbow.
        let (rendered, summary) = try align("the rainbow is bright in the sky", "the is bright in the sky", targets: [1])
        #expect(rendered == "the -rainbow is bright in the sky")
        #expect(summary.incompleteTargetWords == [WordIndex(1)])
        #expect(summary.incompleteNonTargetWords == [])
        #expect(abs(summary.matchShare - 2.0 / 3.0) < 1e-9)
    }

    @Test("Substituted non-targets are listed apart from targets; a substitution never counts as matched")
    func substitutedNonTarget() throws {
        let (_, summary) = try align("the rainbow is bright", "the rainbow is white", targets: [1])
        #expect(summary.incompleteTargetWords == [])
        #expect(summary.incompleteNonTargetWords == [WordIndex(3)])
        #expect(summary.matchShare == 0.5)
    }

    @Test("The 80% rule: 4 of 5 content words matched passes, 3 of 5 doesn't")
    func eightyPercentRule() throws {
        let limit = Thresholds.current.decision.minMatchShare
        let phrase = "green rainbows cover distant hills"
        let (_, fourOfFive) = try align(phrase, "green rainbows cover distant mountains")
        #expect(fourOfFive.matchShare == 0.8)
        #expect(!(fourOfFive.matchShare < limit))
        let (_, threeOfFive) = try align(phrase, "green rainbows cover far mountains")
        #expect(threeOfFive.matchShare == 0.6)
        #expect(threeOfFive.matchShare < limit)
    }

    @Test("More than two non-filler insertions are counted; fillers never are")
    func insertions() throws {
        let limit = Int(Thresholds.current.decision.maxNonFillerInsertions)
        let (_, two) = try align("the rainbow is bright", "um so the rainbow uh is really bright")
        #expect(two.nonFillerInsertions == ["so", "really"])
        #expect(two.nonFillerInsertions.count <= limit)
        let (_, three) = try align("the rainbow is bright", "so the big rainbow is really bright")
        #expect(three.nonFillerInsertions == ["so", "big", "really"])
        #expect(three.nonFillerInsertions.count > limit)
        #expect(three.matchShare == 1)
    }

    @Test("With no content words, the match % is matched words over all words")
    func noContentWords() throws {
        let expected = try starterPhrase("it is in the")
        #expect(expected.words.allSatisfy { !$0.isContent })
        let summary = try aligner.align(expected, heard: try heard("it is on the")).summary
        #expect(summary.matchShare == 0.75)
    }

    @Test("Heard words that go back in time are refused")
    func refusesUnorderedHeardWords() throws {
        let expected = try starterPhrase("the rainbow")
        let said = [
            HeardWord(text: "the", range: try TimeRange(start: 1, end: 1.2)),
            HeardWord(text: "rainbow", range: try TimeRange(start: 0.2, end: 0.6)),
        ]
        #expect(throws: WordAlignment.Invalid.self) { try aligner.align(expected, heard: said) }
    }
}
