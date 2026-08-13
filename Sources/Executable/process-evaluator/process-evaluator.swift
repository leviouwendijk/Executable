import Foundation
import Processes
import Terminal

#if canImport(AppKit)
import AppKit
#endif

public struct ProcessEvaluator: Sendable {
    public struct Options: Sendable {
        public var launchEvenIfNotRunning: Bool
        public var graceMicroseconds: useconds_t

        public init(
            launchEvenIfNotRunning: Bool = false,
            graceMicroseconds: useconds_t = 200_000
        ) {
            self.launchEvenIfNotRunning =
                launchEvenIfNotRunning

            self.graceMicroseconds =
                graceMicroseconds
        }
    }

    public init() {}

    public func relaunch(
        _ directoryURL: URL,
        target: String? = nil,
        options: Options = .init()
    ) async throws {
        let resolved = try AppBundleResolver().resolve(
            directoryURL: directoryURL,
            target: target
        )

        var didTerminate = false

        #if canImport(AppKit)
        if let bundleIdentifier =
            resolved.bundleIdentifier
        {
            let running =
                NSRunningApplication
                    .runningApplications(
                        withBundleIdentifier:
                            bundleIdentifier
                    )

            if !running.isEmpty {
                print(
                    "    [RUNNING] \(bundleIdentifier) → "
                    + running
                        .map {
                            String(
                                $0.processIdentifier
                            )
                        }
                        .joined(
                            separator: ","
                        )
                )

                for app in running {
                    _ = app.terminate()
                }

                for app in running {
                    guard !app.isTerminated else {
                        continue
                    }

                    try? await Task.sleep(
                        for: .microseconds(
                            Int64(
                                options
                                    .graceMicroseconds
                            )
                        )
                    )

                    if !app.isTerminated {
                        _ = app.forceTerminate()
                    }
                }

                didTerminate = true

                print(
                    "    [STOPPED] \(bundleIdentifier)"
                )
            } else {
                print(
                    "    [NOT RUNNING] \(bundleIdentifier)"
                )
            }
        } else {
            print(
                "    [INFO] No bundle identifier; using CLI fallbacks."
            )
        }
        #endif

        if !didTerminate {
            let exact = try? await run(
                path: "/usr/bin/pgrep",
                arguments: [
                    "-x",
                    resolved.executableName,
                ],
                workingDirectory: directoryURL
            )

            let exactPIDText =
                successfulOutput(
                    exact
                )

            print(
                "    [CHECK pgrep -x] "
                + (
                    exactPIDText.map {
                        "\(resolved.executableName) \($0)"
                    }
                    ?? "(no exact name match)"
                )
            )

            if exactPIDText != nil {
                _ = try? await run(
                    path: "/usr/bin/killall",
                    arguments: [
                        "-TERM",
                        resolved.executableName,
                    ],
                    workingDirectory:
                        directoryURL
                )

                print(
                    "    [STOPPED] \(resolved.executableName)"
                )

                didTerminate = true
            } else {
                let bundleMatch = try? await run(
                    path: "/usr/bin/pgrep",
                    arguments: [
                        "-f",
                        resolved.appBundleURL.path,
                    ],
                    workingDirectory:
                        directoryURL
                )

                if let bundlePIDText =
                    successfulOutput(
                        bundleMatch
                    )
                {
                    print(
                        "    [CHECK pgrep -f] \(bundlePIDText)"
                    )

                    _ = try? await run(
                        path: "/usr/bin/killall",
                        arguments: [
                            "-TERM",
                            resolved.executableName,
                        ],
                        workingDirectory:
                            directoryURL
                    )

                    print(
                        "    [STOPPED] \(resolved.executableName)"
                    )

                    didTerminate = true
                } else {
                    print(
                        "    [NOT RUNNING] \(resolved.executableName)"
                    )
                }
            }
        }

        if didTerminate
            || options.launchEvenIfNotRunning
        {
            let result = try await run(
                path: "/usr/bin/open",
                arguments: [
                    resolved.appBundleURL.path,
                ],
                workingDirectory:
                    directoryURL
            )

            try requireSuccess(
                result,
                path: "/usr/bin/open"
            )

            print(
                "    [RE-LAUNCHED] \(resolved.appBundleURL.lastPathComponent)"
                    .ansi(
                        .green
                    )
            )
        }
    }
}

private extension ProcessEvaluator {
    func run(
        path: String,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> ProcessResult {
        try await ProcessRunner().run(
            .init(
                executable: .path(
                    path
                ),
                arguments: arguments,
                workingDirectory:
                    workingDirectory
            )
        )
    }

    func successfulOutput(
        _ result: ProcessResult?
    ) -> String? {
        guard let result else {
            return nil
        }

        guard case .exited(0) =
            result.exit
        else {
            return nil
        }

        let output =
            result.stdoutText
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !output.isEmpty else {
            return nil
        }

        return output
    }

    func requireSuccess(
        _ result: ProcessResult,
        path: String
    ) throws {
        guard case .exited(0) =
            result.exit
        else {
            throw ProcessEvaluatorError
                .commandFailed(
                    path: path,
                    exitCode:
                        conventionalExitCode(
                            result.exit
                        ),
                    stderr:
                        result.stderrText
                )
        }
    }

    func conventionalExitCode(
        _ exit: ProcessExit
    ) -> Int32 {
        switch exit {
        case .exited(
            let code
        ):
            return code

        case .signaled(
            let signal
        ):
            return 128 + signal
        }
    }
}
