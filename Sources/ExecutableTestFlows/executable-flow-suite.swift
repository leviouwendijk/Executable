import TestFlows

enum ExecutableFlowSuite: TestFlowRegistry {
    static let title = "Executable flow tests"

    static let flows: [TestFlow] = [
        targetsFlow,
        productsFlow,
        packageIntrospectionFlow,
        resolveFlow,
        buildLibraryFlow,
        processEvaluatorFlow,
        swiftPMProcessesFlow,
        objectRenewerFlow,
        buildFlow,
        buildWorkflowFlow,
        packageCommandFlow,
        commandFamilyFlow,
        versionCommandFlow,
        appCommandFlow,
        swiftRunFlow,
    ]
}
