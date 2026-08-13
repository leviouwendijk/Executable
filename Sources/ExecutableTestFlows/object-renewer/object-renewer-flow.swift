import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var objectRenewerFlow: TestFlow {
        TestFlow(
            "object-renewer",
            tags: [
                "object-renewer",
                "process",
                "regression",
            ]
        ) {
            Step("execute compile command through Processes") {
                let directory = FileManager.default
                    .temporaryDirectory

                _ = try await ObjectRenewer.executeCommand(
                    in: directory,
                    launchPath: "/bin/sh",
                    arguments: [
                        "-c",
                        "printf success",
                    ],
                    displayName: "fixture",
                    teeOutput: false
                )
            }

            Step("nonzero compile command remains failure") {
                let directory = FileManager.default
                    .temporaryDirectory

                try await Expect.throwsError(
                    "object-renewer.nonzero"
                ) {
                    _ = try await ObjectRenewer.executeCommand(
                        in: directory,
                        launchPath: "/bin/sh",
                        arguments: [
                            "-c",
                            "printf failure >&2; exit 7",
                        ],
                        displayName: "fixture",
                        teeOutput: false
                    )
                }
            }
        }
    }
}
