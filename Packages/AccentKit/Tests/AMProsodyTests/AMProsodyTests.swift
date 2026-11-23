import Testing
import AMProsody

@Test("AMProsody names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMProsodyModule.name == "AMProsody")
    #expect(AMProsodyModule.dependencies == ["AMCore", "AMAlignment", "AMPitch"])
}
