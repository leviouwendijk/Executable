import Arguments
import Foundation
import Path

/// Package alias first, operation second: `sbm pkg runtime update --verify`.
/// No child commands here: both positionals are resolved by Arguments, preserving native help.
public enum SwiftPackageScopedCommand: RunnableArgumentCommand {
    public static let name = "pkg"
    public static let aliases = ["p"]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("Run a typed operation against one package alias in .sbm/workflows.pkl."),
            arg("reference", as: String.self, help: "Package alias declared under packages { }."),
            arg("action", as: String.self, help: "update, verify, or ship."),
            opt("workspace", as: String.self, help: "Workspace root; defaults to upward discovery."),
            opt("configuration", as: String.self, help: "debug (default) or release."),
            opt("branch", as: String.self, help: "Expected Git branch for publication (default: master)."),
            opt("message", short: "m", as: String.self, help: "Commit message for ship."),
            flag("verify", short: "v", help: "After update, build and run tests.primary."),
            flag("ship", help: "After update, build, test, commit and push."),
            flag("stage-all", help: "Explicitly authorize the Git publisher's git add -- . behavior."),
            flag("dry-run", help: "Show the package operation plan without executing."),
        ]
    }

    public static func run(_ invocation: ParsedInvocation) async throws {
        let reference = try invocation.require("reference", as: String.self)
        let rawAction = try invocation.require("action", as: String.self)
        guard let action = WorkflowPackagePlanning.Action(rawValue: rawAction) else {
            throw WorkflowPackagePlanning.Error.invalidAction(rawAction)
        }
        let verify = try invocation.flag("verify")
        let ship = try invocation.flag("ship")
        let dryRun = try invocation.flag("dry-run")
        let stageAll = try invocation.flag("stage-all")
        let message = try invocation.value("message", as: String.self)
        let publishes = action == .ship || ship
        guard action == .update || (!verify && !ship) else {
            throw WorkflowPackagePlanning.Error.invalidOptions("--verify/-v and --ship apply only to update")
        }
        guard publishes || message == nil else {
            throw WorkflowPackagePlanning.Error.invalidOptions("--message is only applicable to ship")
        }
        guard publishes || !stageAll else {
            throw WorkflowPackagePlanning.Error.invalidOptions("--stage-all requires ship")
        }
        // GitManagerAction.commit currently stages the entire repository; require explicit acknowledgement.
        guard !publishes || dryRun || stageAll else {
            throw WorkflowPackagePlanning.Error.invalidOptions("ship requires --stage-all: Git stages all repository changes")
        }
        if publishes && !dryRun && (message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            throw WorkflowConfigurationError.missingMessage
        }
        let mode: Build.Config.Mode
        switch try invocation.value("configuration", as: String.self) ?? "debug" {
        case "debug": mode = .debug
        case "release": mode = .release
        default: throw WorkflowPackagePlanning.Error.invalidOptions("--configuration must be debug or release")
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let workspace: WorkflowPlanning.Workspace
        if let raw = try invocation.value("workspace", as: String.self) {
            let resolved = try PathResolver.resolveURL(raw, relativeTo: .directoryURL(cwd), terminalHint: .directory)
            workspace = try WorkflowPlanning.load(root: resolved)
        } else {
            workspace = try WorkflowPlanning.discover(startingAt: cwd)
        }
        let plan = try await WorkflowPackagePlanning.resolve(
            reference,
            in: workspace,
            action: action,
            verifyAfterUpdate: verify,
            shipAfterUpdate: ship,
            configuration: mode,
            branch: try invocation.value("branch", as: String.self) ?? "master"
        )
        if dryRun {
            WorkflowPlanning.present(plan)
            return
        }
        if publishes {
            print("Package publish authorized (--stage-all): git add -- . may include unrelated changes in \(reference).")
        }
        try await WorkflowExecution.execute(plan, message: message, allowPublish: publishes)
    }
}
