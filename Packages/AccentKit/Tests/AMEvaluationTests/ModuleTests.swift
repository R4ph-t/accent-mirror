import Testing
import AMEvaluation

@Test("AMEvaluation names itself and its allowed dependencies") func moduleIdentifiesItselfAndItsDependencies() {
    #expect(AMEvaluationModule.name == "AMEvaluation")
    #expect(AMEvaluationModule.dependencies == ["AMCore"])
}
