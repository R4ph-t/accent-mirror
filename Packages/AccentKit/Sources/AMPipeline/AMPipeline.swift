// AMPipeline: wires the stages into one end-to-end analysis.
// Placeholder from spec 00; real types arrive in later specs.

import Foundation
import AMCore
import AMCapture
import AMAlignment
import AMPitch
import AMProsody
import AMWarp
import AMLibrary

/// Identifies the `AMPipeline` module and the modules it may depend on.
public enum AMPipelineModule {
    public static let name = "AMPipeline"
    public static let dependencies: [String] = [AMCoreModule.name, AMCaptureModule.name, AMAlignmentModule.name, AMPitchModule.name, AMProsodyModule.name, AMWarpModule.name, AMLibraryModule.name]
}
