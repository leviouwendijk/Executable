import Foundation
import Processes

public enum AppBundleExecution {
    public enum Mode: Sendable, Equatable {
        case open(newInstance: Bool)
        case executable
        case reveal
    }

    public struct Plan: Sendable {
        public let info: AppBundleInfo
        public let executable: URL
        public let arguments: [String]
        public let mode: Mode

        public init(
            info: AppBundleInfo,
            executable: URL,
            arguments: [String],
            mode: Mode
        ) {
            self.info = info
            self.executable = executable
            self.arguments = arguments
            self.mode = mode
        }
    }

    public struct Result: Sendable {
        public let plan: Plan
        public let isSuccess: Bool
        public let exitCode: Int32?
        public let signal: Int32?
        public let stdout: Data
        public let stderr: Data

        public init(
            plan: Plan,
            isSuccess: Bool,
            exitCode: Int32?,
            signal: Int32?,
            stdout: Data,
            stderr: Data
        ) {
            self.plan = plan
            self.isSuccess = isSuccess
            self.exitCode = exitCode
            self.signal = signal
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public static func plan(
        _ info: AppBundleInfo,
        mode: Mode,
        arguments: [String] = []
    ) -> Plan {
        switch mode {
        case .reveal:
            return Plan(
                info: info,
                executable: URL(
                    fileURLWithPath: "/usr/bin/open"
                ),
                arguments: [
                    "-R",
                    info.appBundleURL.path,
                ],
                mode: mode
            )

        case .executable:
            return Plan(
                info: info,
                executable: info.appBundleURL
                    .appendingPathComponent(
                        "Contents/MacOS/\(info.executableName)"
                    ),
                arguments: arguments,
                mode: mode
            )

        case .open(let newInstance):
            var openArguments: [String] = []

            if newInstance {
                openArguments.append(
                    "-n"
                )
            }

            openArguments.append(
                info.appBundleURL.path
            )

            if !arguments.isEmpty {
                openArguments.append(
                    "--args"
                )
                openArguments.append(
                    contentsOf: arguments
                )
            }

            return Plan(
                info: info,
                executable: URL(
                    fileURLWithPath: "/usr/bin/open"
                ),
                arguments: openArguments,
                mode: mode
            )
        }
    }

    @discardableResult
    public static func run(
        _ plan: Plan
    ) async throws -> Result {
        let process = try await ProcessRunner().run(
            .init(
                executable: .path(
                    plan.executable.path
                ),
                arguments: plan.arguments,
                io: .pipes,
                outputLimit: .max
            )
        )

        return Result(
            plan: plan,
            isSuccess: process.isSuccess,
            exitCode: process.exitCode,
            signal: process.signal,
            stdout: process.stdout,
            stderr: process.stderr
        )
    }
}
