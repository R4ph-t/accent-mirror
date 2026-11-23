import Testing
import AMWarp

@Test("AMWarp names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMWarpModule.name == "AMWarp")
    #expect(AMWarpModule.dependencies == ["AMCore", "AMPitch"])
}
