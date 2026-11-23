// AMCapture: recording and importing takes.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore

/// Identifies the `AMCapture` module and the modules it may depend on.
public enum AMCaptureModule {
    public static let name = "AMCapture"
    public static let dependencies: [String] = [AMCoreModule.name]
}
