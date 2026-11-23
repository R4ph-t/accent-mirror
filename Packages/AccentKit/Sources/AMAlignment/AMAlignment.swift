// AMAlignment: word timings from replayed or live ASR.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore

/// Identifies the `AMAlignment` module and the modules it may depend on.
public enum AMAlignmentModule {
    public static let name = "AMAlignment"
    public static let dependencies: [String] = [AMCoreModule.name]
}
