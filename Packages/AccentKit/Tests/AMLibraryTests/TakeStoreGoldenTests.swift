// Spec 28: the take store (spec 16) reads a take saved before scoring could be off (the legacy scored golden) and a
// `.notScored` take (the new golden) from disk, byte for byte, and never rewrites either on open.

import AMCore
import AMLibrary
import Foundation
import Testing

@Suite("Take store reads the spec 28 goldens") struct TakeStoreGoldenTests {
    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("AMCoreTests/Golden")

    static func stored(_ file: String, n: Int) async throws -> (bytes: Data, served: Data, recomputes: Int) {
        let fixture = try TakeStoreFixture()
        let bytes = try Data(contentsOf: golden.appendingPathComponent(file))
        let base = fixture.record(n)
        let record = TakeRecord(
            takeID: base.takeID, phraseID: base.phraseID, recording: base.recording, recordedAt: base.recordedAt,
            audioSHA256: base.audioSHA256, samples: base.samples,
            derived: base.derived.map { $0.level == .l2 ? DerivedRecord(level: .l2, key: $0.key, bytes: bytes) : $0 })
        _ = try await fixture.store().save(record)
        let relaunched = fixture.store()
        _ = await relaunched.recover()
        let served = try await relaunched.result(take: fixture.ref(n), voice: TakeStoreFixture.voice)
        return (bytes, served.bytes, fixture.recomputer.recomputes)
    }

    @Test("the legacy scored take opens as stored: scored, scoringMode .on, no rewrite")
    func legacyScored() async throws {
        let (bytes, served, recomputes) = try await Self.stored("analysed-legacy-scored.json", n: 1)
        #expect(served == bytes, "served from disk unchanged")
        #expect(recomputes == 0, "never rewritten on open")
        let response = try CanonicalJSON.decoder().decode(AnalysisResponse.self, from: served)
        guard case .analysed(let result) = response.outcome else {
            Issue.record("expected analysed")
            return
        }
        #expect(result.verdict == .close && result.identity.scoringMode == .on)
        #expect(result.describe == nil && result.comparableCoverage == nil)
    }

    @Test("the not-scored take opens as stored: .notScored, scoringMode .off")
    func notScored() async throws {
        let (bytes, served, recomputes) = try await Self.stored("analysed-not-scored.json", n: 2)
        #expect(served == bytes && recomputes == 0)
        let response = try CanonicalJSON.decoder().decode(AnalysisResponse.self, from: served)
        guard case .analysed(let result) = response.outcome else {
            Issue.record("expected analysed")
            return
        }
        #expect(result.verdict == .notScored && result.identity.scoringMode == .off)
        #expect(result.describe != nil && result.comparableCoverage != nil)
    }
}
