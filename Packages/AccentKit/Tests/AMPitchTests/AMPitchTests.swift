import Testing
import AMPitch

@Test("AMPitch names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMPitchModule.name == "AMPitch")
    #expect(AMPitchModule.dependencies == ["AMCore"])
}
