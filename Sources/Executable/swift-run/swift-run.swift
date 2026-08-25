import Foundation
import Processes

public enum SwiftRun {
    public struct Request:
        Sendable,
        Hashable
    {
        public let product: String
        public let arguments: [String]

        public init(
            product: String,
            arguments: [String] = []
        ) {
            self.product = product
            self.arguments = arguments
        }
    }

    public struct Options:
        Sendable
    {
        public let outputLimit: Int
        public let timeout: Duration?

        public init(
            outputLimit: Int = 16 * 1024 * 1024,
            timeout: Duration? = nil
        ) {
            self.outputLimit = outputLimit
            self.timeout = timeout
        }
    }

    public struct Result:
        Sendable
    {
        public let product: String
        public let processIdentifier: Int64
        public let isSuccess: Bool
        public let exitCode: Int32?
        public let signal: Int32?
        public let stdout: Data
        public let stderr: Data

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

        public init(
            product: String,
            processIdentifier: Int64,
            isSuccess: Bool,
            exitCode: Int32?,
            signal: Int32?,
            stdout: Data,
            stderr: Data
        ) {
            self.product = product
            self.processIdentifier = processIdentifier
            self.isSuccess = isSuccess
            self.exitCode = exitCode
            self.signal = signal
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public static func run(
        _ request: Request,
        at packageDirectory: URL,
        options: Options = .init()
    ) async throws -> Result {
        let products = try await Products.executables(
            in: packageDirectory
        )

        let available = products
            .map(\.name)
            .sorted()

        guard available.contains(
            request.product
        ) else {
            throw SwiftRunError.productNotFound(
                product: request.product,
                available: available
            )
        }

        let processResult = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/env"
                ),
                arguments: [
                    "swift",
                    "run",
                    request.product,
                ] + request.arguments,
                workingDirectory: packageDirectory,
                environment: .inheritedUpdating(
                    [
                        "NSUnbufferedIO": "YES",
                    ]
                ),
                io: .pipes,
                outputLimit: options.outputLimit,
                timeout: options.timeout
            )
        )

        return .init(
            product: request.product,
            processIdentifier:
                processResult.processIdentifier,
            isSuccess:
                processResult.isSuccess,
            exitCode:
                processResult.exitCode,
            signal:
                processResult.signal,
            stdout:
                processResult.stdout,
            stderr:
                processResult.stderr
        )
    }
}
