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
        [about("Inspect and plan workspace workflows; execution is reserved for a later pass.")]
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
            about("Resolve and display one workflow without running it."),
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
            about("Plan a workflow; --dry-run is mandatory until execution is implemented."),
            arg("name", as: String.self, help: "Named workflow to plan."),
            opt("workspace", as: String.self, help: "Explicit workspace root."),
            opt("from", as: String.self, help: "Start at the named package alias."),
            flag("dry-run", help: "Resolve and display actions without executing them."),
        ]
    }
    public static func run(_ invocation: ParsedInvocation) async throws {
        guard try invocation.flag("dry-run") else { throw WorkflowConfigurationError.readOnly }
        let name = try invocation.require("name", as: String.self)
        let startAlias = try invocation.value("from", as: String.self)
        let workspace = try WorkflowCLI.workspace(try invocation.value("workspace", as: String.self))
        let plan = try await WorkflowPlanning.resolve(name, in: workspace, from: startAlias)
        WorkflowPlanning.present(plan)
    }
}
