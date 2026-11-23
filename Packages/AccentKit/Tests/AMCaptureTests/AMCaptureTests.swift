import Testing
import AMCapture

@Test("AMCapture names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMCaptureModule.name == "AMCapture")
    #expect(AMCaptureModule.dependencies == ["AMCore"])
}
