// AMPitch: F0 tracking (own YIN/pYIN on Accelerate behind PitchTracker).
// The module marker; the tracker, track and axis types live in their own files (spec 04).

import Foundation
import AMCore

/// Identifies the `AMPitch` module and the modules it may depend on.
public enum AMPitchModule {
    public static let name = "AMPitch"
    public static let dependencies: [String] = [AMCoreModule.name]
}
