// Persistence status (plan §8.3). The coordinator publishes the `AnalysisResponse` first, then these updates for
// the same request ID. Storage failures live here, never in `OperationalError`.

import Foundation

public enum PersistenceStatus: Sendable, Hashable, Codable {
    case notSaved(NotSavedReason)
    case pending
    case saved(TakeID)
    case saveFailed(StorageError)
    case savedPruneFailed(TakeID, StorageError)

    enum NotSavedCodingKeys: String, CodingKey { case _0 = "reason" }
    enum SavedCodingKeys: String, CodingKey { case _0 = "take" }
    enum SaveFailedCodingKeys: String, CodingKey { case _0 = "error" }
    enum SavedPruneFailedCodingKeys: String, CodingKey {
        case _0 = "take"
        case _1 = "error"
    }
}

public enum NotSavedReason: String, Sendable, Hashable, Codable, CaseIterable {
    case takeProblem, failed, cancelled, notAccepted
}

/// Why a write, rename or prune of the take store failed (spec 16 maps file-system errors onto these). An `Error` so
/// a `TakePersisting` store can throw it (spec 12); its JSON is unchanged.
public enum StorageError: String, Error, Sendable, Hashable, Codable, CaseIterable {
    case diskFull, permissionDenied, ioFailure
}
