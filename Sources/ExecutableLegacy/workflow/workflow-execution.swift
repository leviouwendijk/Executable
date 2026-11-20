import Executable
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
    private let on_output: (@Sendable (WorkflowExecution.Output) async -> Void)?

    public init(onOutput: (@Sendable (WorkflowExecution.Output) async -> Void)? = nil) {
        self.on_output = onOutput
    }

    public func update(at directory: URL) async throws {
        let result = try await Resolve.getCaptured(at: directory)
        if !result.stdout.isEmpty {
            await on_output?(.combined(String(decoding: result.stdout, as: UTF8.self)))
        }
    }

    public func build(at directory: URL, configuration: Build.Config.Mode) async throws {
        let result = try await Build.captured(
            at: directory,
            config: .init(mode: configuration)
        )
        if !result.stdout.isEmpty {
            await on_output?(.combined(String(decoding: result.stdout, as: UTF8.self)))
        }
    }

    public func test(products: [String], at directory: URL) async throws {
        for product in products {
            let result = try await SwiftRun.run(.init(product: product), at: directory)
            guard result.isSuccess else {
                throw WorkflowExecutionError.testFailed(
                    product: product,
                    exitCode: result.exitCode,
                    signal: result.signal,
                    stdout: result.stdoutText,
                    stderr: result.stderrText
                )
            }
            if !result.stdout.isEmpty { await on_output?(.stdout(result.stdoutText)) }
            if !result.stderr.isEmpty { await on_output?(.stderr(result.stderrText)) }
        }
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
    case testFailed(product: String, exitCode: Int32?, signal: Int32?, stdout: String, stderr: String)

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
        case .testFailed(let product, let code, let signal, let stdout, let stderr):
            return "Test product '\(product)' failed (exit: \(String(describing: code)), signal: \(String(describing: signal))).\n" + stderr + "\n" + stdout
        }
    }
}

/// Sequential, fail-closed interpreter of typed operations. No implicit Git side effects.
public enum WorkflowExecution {
    public enum Output: Sendable {
        case stdout(String)
        case stderr(String)
        case combined(String)
    }

    public enum Event: Sendable {
        case workflowStarted
        case stageStarted(Int)
        case operationStarted(stage: Int, operation: Int)
        case operationCompleted(stage: Int, operation: Int, skipped: Bool)
        case operationFailed(stage: Int, operation: Int, details: String)
        case stageCompleted(Int)
        case stageFailed(Int)
        case workflowCompleted
        case workflowFailed(String)
    }

    public static func execute(
        _ plan: WorkflowPlanning.Plan,
        message: String?,
        allowPublish: Bool,
        performer: any WorkflowOperationPerforming = LiveWorkflowOperationPerformer(),
        onEvent: (@Sendable (Event) async -> Void)? = nil
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

        await onEvent?(.workflowStarted)
        var successful: Set<String> = []
        do {
            for (stage_index, stage) in plan.stages.enumerated() {
                try Task.checkCancellation()
                for prerequisite in stage.needs where !successful.contains(prerequisite) {
                    throw WorkflowExecutionError.prerequisiteUnverified(stage.id, prerequisite)
                }
                await onEvent?(.stageStarted(stage_index))
                do {
                    var verified = false
                    for (operation_index, operation) in stage.operations.enumerated() {
                        try Task.checkCancellation()
                        await onEvent?(.operationStarted(stage: stage_index, operation: operation_index))
                        var skipped = false
                        do {
                            switch operation {
                            case .update(let condition):
                                if condition == .never {
                                    skipped = true
                                } else {
                                    // Preserve the conservative dependency_stale policy.
                                    try await performer.update(at: stage.directory)
                                }
                            case .build(let configuration):
                                try await performer.build(at: stage.directory, configuration: configuration)
                                verified = true
                            case .test(let runs):
                                for run in runs {
                                    try await performer.test(products: run.products, at: run.package)
                                }
                                verified = true
                            case .publish(let policy):
                                if policy.guardCondition == .never || (!policy.commit && !policy.push) {
                                    skipped = true
                                } else {
                                    guard policy.guardCondition != .verified || verified else {
                                        throw WorkflowExecutionError.prerequisiteUnverified(stage.id, "build/test")
                                    }
                                    let commit_message = policy.message == "$message" ? suppliedMessage : policy.message
                                    if policy.commit && commit_message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        throw WorkflowConfigurationError.missingMessage
                                    }
                                    try await performer.publish(
                                        at: stage.directory, branch: stage.branch, message: commit_message,
                                        commit: policy.commit, push: policy.push
                                    )
                                }
                            }
                            await onEvent?(.operationCompleted(
                                stage: stage_index, operation: operation_index, skipped: skipped
                            ))
                        } catch {
                            await onEvent?(.operationFailed(
                                stage: stage_index, operation: operation_index,
                                details: diagnostic(error)
                            ))
                            throw error
                        }
                    }
                    successful.insert(stage.id)
                    await onEvent?(.stageCompleted(stage_index))
                } catch {
                    await onEvent?(.stageFailed(stage_index))
                    throw error
                }
            }
            await onEvent?(.workflowCompleted)
        } catch {
            await onEvent?(.workflowFailed(diagnostic(error)))
            throw error
        }
    }

    private static func diagnostic(_ error: any Error) -> String {
        if case BuildError.swiftFailed(let exit_code, let stdout, let stderr) = error {
            let evidence = stderr.isEmpty ? stdout : stderr + "\n" + stdout
            return "Swift build failed (exit \(exit_code), combined PTY output):\n" + evidence
        }
        if let localized = error as? LocalizedError, let detail = localized.errorDescription {
            return detail
        }
        return String(describing: error)
    }
}
