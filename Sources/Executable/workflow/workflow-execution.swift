import Foundation
import Interfaces

/// An injection seam for isolated workflow tests: implementations do not infer success from output text.
public protocol WorkflowOperationPerforming: Sendable {
    func update(at directory: URL) async throws
    func build(at directory: URL, configuration: Build.Config.Mode) async throws
    func test(products: [String], at directory: URL) async throws
    func publish(at directory: URL, branch: String, message: String, commit: Bool, push: Bool) async throws
}

/// Explicit mutation adapter. Git is owned by Interfaces; package resolution by Executable.
public struct LiveWorkflowOperationPerformer: WorkflowOperationPerforming {
    public init() {}

    public func update(at directory: URL) async throws {
        _ = try await Package.update(at: directory)
    }

    public func build(at directory: URL, configuration: Build.Config.Mode) async throws {
        _ = try await Build.build(at: directory, config: .init(mode: configuration, updateBuiltOnSuccess: false))
    }

    public func test(products: [String], at directory: URL) async throws {
        try await Tests.execute(.init(project: directory, products: products))
    }

    public func publish(at directory: URL, branch: String, message: String, commit: Bool, push: Bool) async throws {
        let actual = try await GitRepo.gitOut(directory, ["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard actual == branch else {
            throw WorkflowExecutionError.wrongBranch(directory, expected: branch, actual: actual)
        }
        let unresolved = try await GitRepo.gitOut(directory, ["diff", "--name-only", "--diff-filter=U"])
        guard unresolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkflowExecutionError.conflictedRepository(directory)
        }
        let upstream = try await GitRepo.defaultRemoteAndBranch(directory)
        guard upstream.branch == branch else {
            throw WorkflowExecutionError.wrongBranch(directory, expected: branch, actual: upstream.branch)
        }
        let changed = try await GitRepo.gitOut(directory, ["status", "--porcelain"])
        if commit && !changed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Publishing changes in \(directory.lastPathComponent):\n\(changed)")
            _ = try await GitManagerAction.commit(message: message, push: false, at: directory)
        }
        if push {
            // Push even if no new commit was needed: there may be existing ahead commits.
            _ = try await GitManagerAction.push(at: directory)
        }
    }
}

public enum WorkflowExecutionError: Error, LocalizedError, Sendable {
    case prerequisiteUnverified(String, String)
    case wrongBranch(URL, expected: String, actual: String)
    case conflictedRepository(URL)
    case noMutationAuthorized

    public var errorDescription: String? {
        switch self {
        case .prerequisiteUnverified(let stage, let prerequisite):
            return "Stage '\(stage)' cannot start: prerequisite '\(prerequisite)' was not verified in this run."
        case .wrongBranch(let directory, let expected, let actual):
            return "Refusing publish at \(directory.path): expected branch '\(expected)', found '\(actual)'."
        case .conflictedRepository(let directory):
            return "Refusing publish with unresolved Git conflicts at \(directory.path)."
        case .noMutationAuthorized:
            return "Workflow execution requires explicit --execute. Publishing additionally requires --publish."
        }
    }
}

/// Sequential, fail-closed interpreter of typed operations. No implicit Git side effects.
public enum WorkflowExecution {
    public static func execute(
        _ plan: WorkflowPlanning.Plan,
        message: String?,
        allowPublish: Bool,
        performer: any WorkflowOperationPerforming = LiveWorkflowOperationPerformer()
    ) async throws {
        if plan.includesPublication && !allowPublish {
            throw WorkflowConfigurationError.publishNotAuthorized
        }
        let suppliedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if (plan.requiresMessage || plan.stages.contains(where: { stage in
            stage.operations.contains { operation in
                if case .publish(let p) = operation { return p.commit && p.message == "$message" }
                return false
            }
        })) && suppliedMessage.isEmpty {
            throw WorkflowConfigurationError.missingMessage
        }

        var successful = Set<String>()
        for stage in plan.stages {
            try Task.checkCancellation()
            for prerequisite in stage.needs where !successful.contains(prerequisite) {
                throw WorkflowExecutionError.prerequisiteUnverified(stage.id, prerequisite)
            }
            print("Stage: \(stage.id) [\(stage.package)]")
            var verified = false
            for operation in stage.operations {
                try Task.checkCancellation()
                switch operation {
                case .update(let condition):
                    if condition == .never { continue }
                    // The current dependency_stale policy is intentionally conservative:
                    // without proven remote/revision freshness, update rather than falsely skip.
                    print("Updating SwiftPM dependencies [\(condition.rawValue)]...")
                    try await performer.update(at: stage.directory)
                case .build(let configuration):
                    try await performer.build(at: stage.directory, configuration: configuration)
                    verified = true
                case .test(let products):
                    try await performer.test(products: products, at: stage.directory)
                    verified = true
                case .publish(let policy):
                    guard policy.guardCondition != .never else { continue }
                    guard policy.guardCondition != .verified || verified else {
                        throw WorkflowExecutionError.prerequisiteUnverified(stage.id, "build/test")
                    }
                    guard policy.commit || policy.push else { continue }
                    let commitMessage = policy.message == "$message" ? suppliedMessage : policy.message
                    if policy.commit && commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw WorkflowConfigurationError.missingMessage
                    }
                    try await performer.publish(
                        at: stage.directory, branch: stage.branch, message: commitMessage,
                        commit: policy.commit, push: policy.push
                    )
                }
            }
            successful.insert(stage.id)
        }
    }
}
