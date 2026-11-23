import Testing
import AMCore

@Test("AMCore names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMCoreModule.name == "AMCore")
    #expect(AMCoreModule.dependencies.isEmpty)
}
