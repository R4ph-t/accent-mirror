import Testing
import AMPipeline
import AMPlacement
import AMProsody
import AMVerdicts

@Test("AMPipeline names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMPipelineModule.name == "AMPipeline")
    #expect(AMPipelineModule.dependencies == ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody", "AMWarp", "AMLibrary"])
}
