import Testing
@testable import AMPlacement

@Test func moduleDependsOnlyOnShippedLeaves() {
    #expect(AMPlacementModule.name == "AMPlacement")
    #expect(AMPlacementModule.dependencies == ["AMCore", "AMCapture", "AMAlignment", "AMPitch", "AMProsody"])
}
