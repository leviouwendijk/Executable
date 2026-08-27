import Arguments
import Foundation
import Terminal

public enum SwiftAppExecCommand: RunnableArgumentCommand {
    public static let name = "x"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Try to execute the app bundle in this project."
            ),
            opt(
                "project",
                short: "p",
                as: String.self,
                help: "Project directory (defaults to CWD)."
            ),
            opt(
                "app-name",
                as: String.self,
                help: "App (bundle) name. Defaults to --app-name OR --target OR <Package.name> OR folder name."
            ),
            opt(
                "target",
                as: String.self,
                help: "Executable target name used for defaulting."
            ),
            flag(
                "dry-run",
                help: "Print what would run, then exit."
            ),
            flag(
                "reveal",
                help: "Reveal the .app in Finder instead of running it."
            ),
            flag(
                "exec",
                help: "Launch by executing the bundle's binary instead of `open`."
            ),
            flag(
                "no-new-instance",
                help: "When using `open`, don't force a new instance (-n)."
            ),
            arg(
                "app-args",
                as: String.self,
                arity: .variadic,
                help: "Arguments forwarded to the app. Use -- before option-like app arguments."
            ),
        ]
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        let project = try invocation.value(
            "project",
            as: String.self
        ).map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        let packageName = (try? await Package.name(
            at: project
        )) ?? project.lastPathComponent

        let appName = try invocation.value(
            "app-name",
            as: String.self
        )

        let target = try invocation.value(
            "target",
            as: String.self
        )

        let resolvedName = appName
            ?? target
            ?? packageName

        let info = try AppBundleResolver().resolve(
            directoryURL: project,
            target: appName ?? resolvedName
        )

        let appArguments = try invocation.values(
            "app-args",
            as: String.self
        ) + invocation.passthrough

        let mode: AppBundleExecution.Mode

        if try invocation.flag("reveal") {
            mode = .reveal
        } else if try invocation.flag("exec") {
            mode = .executable
        } else {
            mode = .open(
                newInstance: !(try invocation.flag("no-new-instance"))
            )
        }

        let plan = AppBundleExecution.plan(
            info,
            mode: mode,
            arguments: appArguments
        )

        print(
            """
            App bundle: \(info.appBundleURL.path)
            Executable: \(info.appBundleURL.appendingPathComponent("Contents/MacOS/\(info.executableName)").path)
            Bundle ID:  \(info.bundleIdentifier ?? "<none>")
            """.ansi(.brightBlack)
        )

        if try invocation.flag("dry-run") {
            let argumentText = plan.arguments.map {
                String(reflecting: $0)
            }.joined(separator: " ")

            print(
                "[dry-run] would run: \(plan.executable.path) \(argumentText)".ansi(.yellow)
            )
            return
        }

        let result = try await AppBundleExecution.run(
            plan
        )

        guard result.isSuccess else {
            throw SwiftAppExecCommandError.executionFailed(
                result.exitCode
            )
        }

        if !result.stdout.isEmpty {
            print(
                String(
                    decoding: result.stdout,
                    as: UTF8.self
                ),
                terminator: ""
            )
        }

        if !result.stderr.isEmpty {
            fputs(
                String(
                    decoding: result.stderr,
                    as: UTF8.self
                ),
                stderr
            )
        }
    }
}

public enum SwiftAppExecCommandError:
    Error,
    Sendable,
    LocalizedError,
    Equatable
{
    case executionFailed(Int32?)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let code):
            let description = code.map(
                String.init
            ) ?? "unknown"

            return "App execution failed with exit code \(description)."
        }
    }
}
