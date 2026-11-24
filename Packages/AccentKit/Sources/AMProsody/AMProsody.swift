// AMProsody: stress, rhythm and intonation features.
// Spec 07: the L1 syllable segmenter. Spec 08: prominence and its display. Spec 28 moved observed stress, A(w) and
// the placement rule to AMPlacement; the pure measure helpers (`PitchStatistics`) moved down here from AMScoring.

import Foundation
import AMCore
import AMAlignment
import AMPitch

/// Identifies the `AMProsody` module and the modules it may depend on.
public enum AMProsodyModule {
    public static let name = "AMProsody"
    public static let dependencies: [String] = [AMCoreModule.name, AMAlignmentModule.name, AMPitchModule.name]
}
