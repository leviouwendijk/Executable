import Foundation

/// Compiles a single package action to the same typed IR as full workspace workflows.
/// It does not inherit stage `needs` or publish policies from unrelated workflows.
public enum WorkflowPackagePlanning {
    public enum Action: String, Sendable {
        case update
        case verify
        case ship
    }

    public enum Error: Swift.Error, LocalizedError, Sendable {
        case invalidAction(String)
        case invalidOptions(String)

        public var errorDescription: String? {
            switch self {
            case .invalidAction(let value):
                return "Unknown package action '\(value)'. Choose update, verify, or ship."
            case .invalidOptions(let detail):
                return "Invalid package command: \(detail)"
            }
        }
    }

    public static func resolve(
        _ reference: String,
        in workspace: WorkflowPlanning.Workspace,
        action: Action,
        verifyAfterUpdate: Bool = false,
        shipAfterUpdate: Bool = false,
        configuration: Build.Config.Mode = .debug,
        branch: String = "master"
    ) async throws -> WorkflowPlanning.Plan {
        guard !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !branch.hasPrefix("-") else {
            throw Error.invalidOptions("--branch must be a nonempty Git branch")
        }
        let directory = try WorkflowPlanning.packageDirectory(reference, in: workspace)
        let update = action == .update
        let publish = action == .ship || shipAfterUpdate
        let verify = action != .update || verifyAfterUpdate || publish
        guard update || (!verifyAfterUpdate && !shipAfterUpdate) else {
            throw Error.invalidOptions("--verify and --ship are only valid for the update action")
        }

        var operations: [WorkflowPlanning.Operation] = []
        if update {
            operations.append(.update(.always))
        }
        if verify {
            // A shipping action must have declared tests, never silently publish an untested package.
            let products = try await Tests.resolve(at: directory, selection: .primary).products
            operations.append(.build(configuration))
            operations.append(.test(products))
        }
        if publish {
            operations.append(.publish(.init(
                guardCondition: .verified,
                commit: true,
                push: true,
                message: "$message"
            )))
        }

        return WorkflowPlanning.Plan(
            name: "pkg \(reference) \(action.rawValue)",
            root: workspace.root,
            source: workspace.source,
            requiresMessage: publish,
            stages: [WorkflowPlanning.Stage(
                id: reference,
                package: reference,
                directory: directory,
                needs: [],
                branch: branch,
                operations: operations
            )]
        )
    }
}
