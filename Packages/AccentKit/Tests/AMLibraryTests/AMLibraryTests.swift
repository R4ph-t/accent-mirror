import Testing
import AMLibrary

@Test("AMLibrary names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMLibraryModule.name == "AMLibrary")
    #expect(AMLibraryModule.dependencies == ["AMCore"])
}
