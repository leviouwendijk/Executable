import Foundation
import Testing

@main
enum ExecutableTestCLI {
    static func main() async {
        let output = ClosureTestTextOutput { text in
            FileHandle.standardOutput.write(Data(text.utf8))
        }
        let reporter = PlainTextTestReporter(
            verbose: CommandLine.arguments.contains("--verbose"),
            output: output
        )
        let result = await TestRunner.run(ExecutableTestSuite.suite, sink: reporter)
        Foundation.exit(result.isFailure ? 1 : 0)
    }
}
