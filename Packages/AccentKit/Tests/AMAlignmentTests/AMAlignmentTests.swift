import Testing
import AMAlignment

@Test("AMAlignment names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMAlignmentModule.name == "AMAlignment")
    #expect(AMAlignmentModule.dependencies == ["AMCore"])
}
