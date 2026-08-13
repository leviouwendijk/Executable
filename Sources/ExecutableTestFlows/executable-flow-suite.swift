import TestFlows

enum ExecutableFlowSuite: TestFlowRegistry {
    static let title = "Executable flow tests"

    static let flows: [TestFlow] = [
        targetsFlow,
        resolveFlow,
        buildLibraryFlow,
        processEvaluatorFlow,
        swiftPMProcessesFlow,
        objectRenewerFlow,
        buildFlow,
    ]
}
