import CryptoKit
import Foundation
import Testing
import AMCore
@testable import AMAlignment

@Test("AMAlignment names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMAlignmentModule.name == "AMAlignment")
    #expect(AMAlignmentModule.dependencies == ["AMCore"])
}

@Suite("Bundled CMUdict")
struct BundledDictionaryTests {
    struct Manifest: Decodable {
        struct File: Decodable {
            let path: String
            let sha256: String
        }

        let commit: String
        let files: [File]
    }

    @Test("Every bundled CMUdict file matches the SHA-256 in its manifest, pinned to a commit")
    func bundledFilesMatchManifest() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: BundledResource.data("CMUdict/manifest.json"))
        #expect(manifest.commit.count == 40)
        #expect(manifest.files.map(\.path).sorted() == ["LICENSE", "cmudict.dict"])
        for file in manifest.files {
            let digest = SHA256.hash(data: try BundledResource.data("CMUdict/\(file.path)"))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            #expect(hex == file.sha256, "\(file.path)")
        }
    }

    @Test("Looks words up case-insensitively, variants in CMUdict order")
    func looksUpVariants() throws {
        let dictionary = try PronouncingDictionary.bundled()
        #expect(dictionary.pronunciations(of: "Record").map(\.arpabet) == [
            "R AH0 K AO1 R D", "R EH1 K ER0 D", "R IH0 K AO1 R D",
        ])
        #expect(dictionary.pronunciations(of: "zzxqv").isEmpty)
        #expect(dictionary.hasStressVariants("record"))
        #expect(dictionary.hasStressVariants("can"))
        #expect(!dictionary.hasStressVariants("station"))
    }

    @Test("Parses comments and numbered variants")
    func parsesFormat() {
        let dictionary = PronouncingDictionary(contents: "aalborg AO1 L B AO0 R G # place, danish\nthe DH AH0\nthe(2) DH AH1\n")
        #expect(dictionary.pronunciations(of: "aalborg").map(\.arpabet) == ["AO1 L B AO0 R G"])
        #expect(dictionary.pronunciations(of: "the").count == 2)
    }
}

@Suite("Stress-shift pairs")
struct StressShiftPairsTests {
    @Test("Lists words whose variants differ in primary stress, with the curated POS variants")
    func listsShiftWords() throws {
        let pairs = try StressShiftPairs.bundled()
        let record = try #require(pairs.entry(for: "record"))
        #expect(record.pronunciation(for: .noun)?.primarySyllable == 0)
        #expect(record.pronunciation(for: .verb)?.primarySyllable == 1)
        #expect(record.pronunciation(for: .other) == nil)
        #expect(pairs.entry(for: "station") == nil)
        // "desert" doesn't follow the pattern: ambiguous for every part of speech.
        let desert = try #require(pairs.entry(for: "desert"))
        #expect(desert.noun == nil && desert.verb == nil && desert.adjective == nil)
        // Every word in the file really has two primary patterns in the bundled dictionary.
        let dictionary = try PronouncingDictionary.bundled()
        for word in ["present", "object", "permit", "increase", "contract", "produce"] {
            let primaries = Set(dictionary.pronunciations(of: word).compactMap(\.primarySyllable))
            #expect(primaries.count > 1, "\(word)")
            #expect(pairs.entry(for: word) != nil, "\(word)")
        }
    }
}
