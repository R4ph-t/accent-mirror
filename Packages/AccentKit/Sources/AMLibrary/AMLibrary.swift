// AMLibrary: starter phrases and the user's saved takes.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore

/// Identifies the `AMLibrary` module and the modules it may depend on.
public enum AMLibraryModule {
    public static let name = "AMLibrary"
    public static let dependencies: [String] = [AMCoreModule.name]
}
