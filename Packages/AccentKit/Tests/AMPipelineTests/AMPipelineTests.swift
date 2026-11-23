import Testing
import AMPipeline

@Test("AMPipeline names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMPipelineModule.name == "AMPipeline")
    #expect(AMPipelineModule.dependencies == ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody", "AMWarp", "AMScoring", "AMLibrary"])
}
