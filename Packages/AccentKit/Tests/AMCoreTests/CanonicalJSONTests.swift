import Foundation
import Testing
import AMCore

@Suite("SHA-256") struct SHA256Tests {
    @Test("matches the FIPS 180-4 test vectors", arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (
            "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        ),
    ])
    func knownVectors(input: String, expected: String) {
        #expect(SHA256Digest.hex(of: Array(input.utf8)) == expected)
    }

    @Test("a million 'a's hashes to the long-message vector") func longMessage() {
        let input = [UInt8](repeating: UInt8(ascii: "a"), count: 1_000_000)
        #expect(SHA256Digest.hex(of: input) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}

@Suite("Canonical JSON") struct CanonicalJSONTests {
    private func canonical(_ json: String) throws -> String {
        String(decoding: try CanonicalJSON.canonicalize(Data(json.utf8)), as: UTF8.self)
    }

    @Test("sorts keys at every level and drops whitespace") func sortsKeys() throws {
        #expect(try canonical(#"{ "b": 1, "a": { "z": true, "y": null } }"#) == #"{"a":{"y":null,"z":true},"b":1}"#)
    }

    @Test("writes integral numbers as integers and others in shortest form") func numbers() throws {
        #expect(try canonical("[2.0, -60, 0.05, 1.6, 1e-7, 0.1]") == "[2,-60,0.05,1.6,1e-07,0.1]")
    }

    @Test("keeps booleans distinct from 0 and 1") func booleans() throws {
        #expect(try canonical("[true, false, 1, 0]") == "[true,false,1,0]")
    }

    @Test("escapes only quotes, backslashes and control characters") func strings() throws {
        #expect(try canonical(#"["a\"b\\c/d\né\u0001"]"#) == #"["a\"b\\c/d\né\u0001"]"#)
    }

    @Test("gives the same bytes whatever the input key order") func orderIndependent() throws {
        struct Pair: Encodable { let alpha: Double; let beta: [Int] }
        let encoded = try CanonicalJSON.encode(Pair(alpha: 0.7, beta: [3, 1]))
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"alpha":0.7,"beta":[3,1]}"#)
        #expect(try canonical(#"{"beta":[3,1],"alpha":0.7}"#) == String(decoding: encoded, as: UTF8.self))
    }

    @Test("refuses non-finite numbers") func nonFinite() {
        #expect(throws: (any Error).self) { try CanonicalJSON.encode([Double.nan]) }
    }
}
