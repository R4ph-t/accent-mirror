import AMCore
import AMLibrary
import AMPipeline
import Foundation
import Testing

// Designer addendum v3.4 (Y1–Y3): readable display syllables on the strip, no ARPAbet phone tokens in any fixture or
// displayed label, every starter phrase's native labels match the bundled table, and `chocolate` uses the
// merged-word fallback. Unhosted: no window, no microphone, no network.

private let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let fixtureRoot = repo.appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory)
private let starterFolder = repo.appending(path: "Resources/Starter", directoryHint: .isDirectory)
private let library = FixtureLibrary(root: fixtureRoot)

@MainActor
@Suite("Addendum v3.4 display syllables and merged-word fallback")
struct AddendumV34Tests {
    private static func hasPhoneToken(_ s: String) -> Bool { s.firstMatch(of: /\b[A-Za-z]+[012]\b/) != nil }

    @Test("No fixture or presented strip label contains an ARPAbet digit-stressed phone token")
    func noDigitStressedPhoneTokenInAnyDisplayedLabel() throws {
        for name in try library.allNames() {
            let loaded = try library.load(name)
            for word in loaded.phrase.words {
                for syllable in word.syllables {
                    #expect(!Self.hasPhoneToken(syllable.text), "\(name) native '\(syllable.text)'")
                }
            }
            if let take = loaded.take {
                for pair in take.words {
                    for syllable in pair.syllables {
                        #expect(!Self.hasPhoneToken(syllable.text), "\(name) you '\(syllable.text)'")
                    }
                }
            }

            let strip = ShellPresenter.strip(loaded)
            for cluster in strip.native {
                if let text = cluster.label?.text {
                    #expect(!Self.hasPhoneToken(text), "\(name) strip native '\(text)'")
                }
            }
            if case .bars(let clusters, _, _) = strip.you {
                for cluster in clusters {
                    if let text = cluster.label?.text {
                        #expect(!Self.hasPhoneToken(text), "\(name) strip you '\(text)'")
                    }
                }
            }
        }
    }

    @Test("Every starter phrase produces readable on-screen native labels matching starter-syllables.json")
    func everyStarterPhraseMatchesDisplayTable() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-app-labels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (refLibrary, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())
        let table = try DisplaySyllableTable.bundled()

        for phrase in refLibrary.manifest.phrases {
            let input = try #require(references.phraseInput(phrase.id))
            let display = try await NativeView.load(phrase: input, voice: phrase.headlineVoice, reference: refLibrary)
            let livePhrase = LivePhrase(phrase: phrase, packTitle: "Starter", voice: phrase.headlineVoice)
            let fixturePhrase = LivePresenter.emptyPhrase(livePhrase, native: display)
            let clusters = ShellPresenter.nativeClusters(fixturePhrase)

            // Every word's presented native labels equal the table (modulo caps on the dotted syllable) and
            // concatenate to the folded word, with zero ARPAbet tokens.
            var cursor = 0
            for (wordIndex, word) in fixturePhrase.words.enumerated() {
                let folded = DisplayWord.fold(word.text)
                let expectedPieces = try #require(table.syllables(forFolded: folded), "\(phrase.id)/\(folded)")
                let wordClusters = Array(clusters[cursor..<(cursor + word.syllables.count)])
                cursor += word.syllables.count

                let labels = wordClusters.compactMap(\.label)
                #expect(labels.count == expectedPieces.count, "\(phrase.id)/\(folded)")
                #expect(labels.allSatisfy { $0.style != .merged }, "\(phrase.id)/\(folded) should be split")
                #expect(labels.map { $0.text.lowercased() } == expectedPieces, "\(phrase.id)/\(folded)")
                #expect(labels.map { $0.text.lowercased() }.joined() == folded, "\(phrase.id)/\(folded)")
                #expect(wordClusters.allSatisfy { $0.word == wordIndex })
                for label in labels {
                    #expect(!Self.hasPhoneToken(label.text), "\(phrase.id) '\(label.text)'")
                }
            }
        }
    }

    @Test("Chocolate mismatch fixture uses merged-word fallback, centred lowercase tertiary, dot under first native syllable")
    func chocolateMismatchFixtureUsesMergedWordFallback() throws {
        #expect(try library.allNames().contains("fallback-merged-word"))
        let loaded = try library.load("fallback-merged-word")
        let strip = ShellPresenter.strip(loaded)

        // Phrase: "The chocolate." -> 1 cluster ("the"), 2 clusters ("chocolate")
        #expect(strip.native.count == 3)
        #expect(strip.native[0].label == ClusterLabel(text: "the", style: .lower))
        #expect(strip.native[0].labelSpan == nil)
        #expect(!strip.native[0].dot)

        // Chocolate cluster 0 carries the single merged label spanning both clusters, plus the Lime dot.
        let expectedSpan = strip.native[1].start...strip.native[2].end
        #expect(strip.native[1].label == ClusterLabel(text: "chocolate", style: .merged))
        #expect(strip.native[1].labelSpan == expectedSpan)
        #expect(strip.native[1].dot)
        #expect(strip.native[1].word == 1)

        // Chocolate cluster 1 has no separate label and no dot.
        #expect(strip.native[2].label == nil)
        #expect(strip.native[2].labelSpan == nil)
        #expect(!strip.native[2].dot)
        #expect(strip.native[2].word == 1)

        // Merged label is never set in caps, uses regular priority.
        #expect(strip.native[1].label?.text == "chocolate")
        #expect(LabelLayout.syllablePriority(.merged) == .low)

        // Your row follows the same merged-word fallback.
        guard case .bars(let youClusters, let slots, let showsLabels) = strip.you else {
            Issue.record("expected you bars")
            return
        }
        #expect(slots.isEmpty && showsLabels)
        #expect(youClusters.count == 3)
        #expect(youClusters[0].label == ClusterLabel(text: "the", style: .yours))
        #expect(youClusters[1].label == ClusterLabel(text: "chocolate", style: .merged))
        #expect(youClusters[1].labelSpan == youClusters[1].start...youClusters[2].end)
        #expect(youClusters[2].label == nil)

        // Timing connectors still join syllable to syllable (3 total: 1 for "the", 2 for "chocolate").
        #expect(strip.connectors.count == 3)
        #expect(!strip.connectors[0].fromDot)
        #expect(strip.connectors[1].fromDot)
        #expect(!strip.connectors[2].fromDot)
    }
}
