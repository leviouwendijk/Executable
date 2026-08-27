import Foundation
import Processes

public enum SwiftCompiler {
    public struct ParseResult: Sendable {
        public let file: URL
        public let isSuccess: Bool
        public let exitCode: Int32?
        public let signal: Int32?
        public let stdout: Data
        public let stderr: Data

        public init(
            file: URL,
            isSuccess: Bool,
            exitCode: Int32?,
            signal: Int32?,
            stdout: Data,
            stderr: Data
        ) {
            self.file = file.standardizedFileURL
            self.isSuccess = isSuccess
            self.exitCode = exitCode
            self.signal = signal
            self.stdout = stdout
            self.stderr = stderr
        }

        public var stdoutText: String {
            String(
                decoding: stdout,
                as: UTF8.self
            )
        }

        public var stderrText: String {
            String(
                decoding: stderr,
                as: UTF8.self
            )
        }
    }

    public static func parse(
        _ file: URL,
        workingDirectory: URL? = nil
    ) async throws -> ParseResult {
        let file = file.standardizedFileURL
        let result = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/xcrun"
                ),
                arguments: [
                    "swiftc",
                    "-parse",
                    file.path,
                ],
                workingDirectory: workingDirectory,
                io: .pipes,
                outputLimit: 4 * 1024 * 1024
            )
        )

        switch result.exit {
        case .exited(let code):
            return .init(
                file: file,
                isSuccess: code == 0,
                exitCode: code,
                signal: nil,
                stdout: result.stdout,
                stderr: result.stderr
            )

        case .signaled(let signal):
            return .init(
                file: file,
                isSuccess: false,
                exitCode: nil,
                signal: signal,
                stdout: result.stdout,
                stderr: result.stderr
            )
        }
    }
}
