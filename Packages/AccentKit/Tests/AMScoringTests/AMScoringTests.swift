import Testing
import AMScoring

@Test("AMScoring names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMScoringModule.name == "AMScoring")
    #expect(AMScoringModule.dependencies == ["AMCore", "AMProsody", "AMWarp"])
}
