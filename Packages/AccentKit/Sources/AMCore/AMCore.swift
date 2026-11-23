// AMCore: domain types, the analysis contract and thresholds. Depends on nothing (Foundation only).
// Placeholder from spec 00; real types arrive in later specs.

import Foundation

/// Identifies the `AMCore` module and the modules it may depend on.
public enum AMCoreModule {
    public static let name = "AMCore"
    public static let dependencies: [String] = []
}
