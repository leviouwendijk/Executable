import Arguments
import Foundation
import Path

public enum SwiftWorkflowCommand: ArgumentCommand {
    public static let name = "wf"
    public static let children: [ArgumentCommandType] = [
        SwiftWorkflowListCommand.self,
        SwiftWorkflowShowCommand.self,
        SwiftWorkflowRunCommand.self,
    ]
    public static func components() throws -> [CommandComponentLowerable] {
        [about("Inspect, plan, and explicitly execute typed workspace workflows.")]
    }
}

private enum WorkflowCLI {
    static func workspace(_ raw: String?) throws -> WorkflowPlanning.Workspace {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let raw {
            let root = try PathResolver.resolveURL(raw, relativeTo: .directoryURL(cwd), terminalHint: .directory)
            return try WorkflowPlanning.load(root: root)
        }
        return try WorkflowPlanning.discover(startingAt: cwd)
    }
}

public enum SwiftWorkflowListCommand: RunnableArgumentCommand {
    public static let name = "list"
    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("List workflow names from the nearest workspace .sbm/workflows.pkl."),
            opt("workspace", as: String.self, help: "Explicit workspace root (defaults to upward discovery)."),
        ]
    }
    public static func run(_ invocation: ParsedInvocation) async throws {
        let workspace = try WorkflowCLI.workspace(try invocation.value("workspace", as: String.self))
        print("Workspace: \(workspace.root.path)")
        for name in workspace.configuration.workflows.keys.sorted() { print("• \(name)") }
    }
}

public enum SwiftWorkflowShowCommand: RunnableArgumentCommand {
    public static let name = "show"
    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("Resolve and display one typed workflow without executing it."),
            arg("name", as: String.self, help: "Named workflow to inspect."),
            opt("workspace", as: String.self, help: "Explicit workspace root."),
        ]
    }
    public static func run(_ invocation: ParsedInvocation) async throws {
        let name = try invocation.require("name", as: String.self)
        let workspace = try WorkflowCLI.workspace(try invocation.value("workspace", as: String.self))
        let plan = try await WorkflowPlanning.resolve(name, in: workspace)
        WorkflowPlanning.present(plan)
    }
}

public enum SwiftWorkflowRunCommand: RunnableArgumentCommand {
    public static let name = "run"
    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("Dry-run by default; real execution requires --execute; Git publish also requires --publish."),
            arg("name", as: String.self, help: "Named workflow to run."),
            opt("workspace", as: String.self, help: "Explicit workspace root."),
            opt("from", as: String.self, help: "Plan starting from this stage id. Execution cannot skip prerequisites yet."),
            opt("message", as: String.self, help: "Commit message supplied to publish operations."),
            flag("dry-run", help: "Resolve and present the plan without performing operations."),
            flag("execute", help: "Execute workflow operations rather than previewing them."),
            flag("publish", help: "Explicitly permit workflow Git commit and push operations."),
        ]
    }
    public static func run(_ invocation: ParsedInvocation) async throws {
        let name = try invocation.require("name", as: String.self)
        let startID = try invocation.value("from", as: String.self)
        let workspace = try WorkflowCLI.workspace(try invocation.value("workspace", as: String.self))
        let plan = try await WorkflowPlanning.resolve(name, in: workspace, from: startID)
        let execute = try invocation.flag("execute")
        let dryRun = try invocation.flag("dry-run")
        let allowPublish = try invocation.flag("publish")
        guard !(execute && dryRun) else {
            throw WorkflowConfigurationError.invalidPolicy("--execute conflicts with --dry-run")
        }
        guard execute else {
            guard !allowPublish else { throw WorkflowConfigurationError.invalidPolicy("--publish requires --execute") }
            WorkflowPlanning.present(plan)
            return
        }
        guard startID == nil else { throw WorkflowConfigurationError.executionFromUnsupported }
        let message = try invocation.value("message", as: String.self)
        try await WorkflowExecution.execute(plan, message: message, allowPublish: allowPublish)
    }
}

