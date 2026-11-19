import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var swiftPMProcessesFlow: TestFlow {
        TestFlow(
            "swiftpm-processes",
            tags: [
                "process",
                "swiftpm",
                "snapshot",
                "regression",
            ]
        ) {
            Step("acquire and decode process snapshot") {
                let processes = try await SwiftPMProcesses()
                    .list()

                try Expect.equal(
                    Set(
                        processes.map(
                            \.pid
                        )
                    ).count,
                    processes.count,
                    "snapshot contains unique process identifiers"
                )

                for process in processes {
                    try Expect.true(
                        process.pid > 0,
                        "matched process has positive pid"
                    )

                    try Expect.false(
                        process.commandLine
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty,
                        "matched process has command line"
                    )
                }
            }
        }
    }
}
