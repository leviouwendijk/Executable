import TestFlows

@main
enum ExecutableTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: ExecutableFlowSuite.self
        )
    }
}
