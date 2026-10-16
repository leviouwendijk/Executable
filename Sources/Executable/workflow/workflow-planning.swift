import Foundation
import Path

/// Read-only compilation from Pkl declarations into typed workflow operations.
public enum WorkflowPlanning {
    public struct Workspace: Sendable {
        public let root: URL
        public let source: URL
        public let configuration: WorkflowConfiguration
    }

    public enum Condition: String, Sendable, Equatable {
        case always
        case never
        case verified
        case dependencyStale = "dependency_stale"
    }

    public struct Publication: Sendable, Equatable {
        public let guardCondition: Condition
        public let commit: Bool
        public let push: Bool
        public let message: String
    }

    public enum Operation: Sendable, Equatable {
        case update(Condition)
        case build(Build.Config.Mode)
        case test([String])
        case publish(Publication)

        public var description: String {
            switch self {
            case .update(let condition): return "update [when: \(condition.rawValue)]"
            case .build(let config): return "build [\(config == .debug ? "debug" : "release")]"
            case .test(let products): return "test: " + products.joined(separator: ", ")
            case .publish(let policy):
                return "publish [when: \(policy.guardCondition.rawValue), commit: \(policy.commit), push: \(policy.push), message: \(policy.message)]"
            }
        }
    }

    public struct Stage: Sendable {
        public let id: String
        public let package: String
        public let directory: URL
        public let needs: [String]
        public let branch: String
        public let operations: [Operation]
    }

    public struct Plan: Sendable {
        public let name: String
        public let root: URL
        public let source: URL
        public let requiresMessage: Bool
        public let stages: [Stage]

        public var includesPublication: Bool {
            stages.contains { stage in
                stage.operations.contains { operation in
                    if case .publish(let policy) = operation { return policy.commit || policy.push }
                    return false
                }
            }
        }
    }

    public static func discover(startingAt start: URL) throws -> Workspace {
        guard let root = PathAncestorSearch.nearestAncestorContainingAny(
            [".sbm/workflows.pkl"], startingAt: start
        ) else {
            throw WorkflowConfigurationError.notFound(start.appendingPathComponent(".sbm/workflows.pkl"))
        }
        return try load(root: root)
    }

    public static func load(root: URL) throws -> Workspace {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let source = canonical.appendingPathComponent(".sbm/workflows.pkl")
        guard source.resolvingSymlinksInPath().standardizedFileURL == source.standardizedFileURL else {
            throw WorkflowConfigurationError.invalidPackagePath(source.path)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WorkflowConfigurationError.notFound(source)
        }
        let configuration = try WorkflowConfiguration.parse(String(contentsOf: source, encoding: .utf8))
        return Workspace(root: canonical, source: source, configuration: configuration)
    }

    public static func resolve(
        _ name: String,
        in workspace: Workspace,
        from startID: String? = nil
    ) async throws -> Plan {
        guard let definition = workspace.configuration.workflows[name] else {
            throw WorkflowConfigurationError.unknownWorkflow(name)
        }
        guard !definition.stages.isEmpty else { throw WorkflowConfigurationError.emptySteps(name) }
        try validateNames(in: workspace.configuration)
        let declared = definition.stages
        var known = Set<String>()
        for stage in declared {
            guard validIdentifier(stage.id) else { throw WorkflowConfigurationError.invalidName(stage.id) }
            guard known.insert(stage.id).inserted else { throw WorkflowConfigurationError.repeatedStep(stage.id) }
        }
        var seen = Set<String>()
        for stage in declared {
            for dependency in stage.needs ?? [] {
                guard known.contains(dependency) else {
                    throw WorkflowConfigurationError.unknownDependency(stage: stage.id, prerequisite: dependency)
                }
                guard seen.contains(dependency) else {
                    throw WorkflowConfigurationError.forwardDependency(stage: stage.id, prerequisite: dependency)
                }
            }
            seen.insert(stage.id)
        }

        let defaults = definition.defaults
        let configuration: Build.Config.Mode
        switch defaults?.configuration ?? "debug" {
        case "debug": configuration = .debug
        case "release": configuration = .release
        default: throw WorkflowConfigurationError.invalidPolicy("configuration")
        }
        guard (defaults?.onFailure ?? "stop") == "stop" else {
            throw WorkflowConfigurationError.invalidPolicy("onFailure (only stop is implemented)")
        }
        guard let branch = defaults?.branch, !branch.isEmpty, !branch.hasPrefix("-") else {
            throw WorkflowConfigurationError.invalidPolicy("defaults.branch is required")
        }
        if let input = definition.inputs?.message, input != "required" {
            throw WorkflowConfigurationError.invalidPolicy("inputs.message = \(input)")
        }

        var planned: [Stage] = []
        for stage in declared {
            let directory = try packageDirectory(stage.package, in: workspace)
            var operations: [Operation] = []
            if stage.update != nil || defaults?.update != nil {
                let when = try condition(stage.update?.when ?? defaults?.update?.when ?? "always", allowed: [.always, .never, .dependencyStale])
                operations.append(.update(when))
            }
            operations.append(.build(configuration))
            if let test = stage.test {
                guard !test.isEmpty else { throw WorkflowConfigurationError.invalidPolicy("empty test for \(stage.id)") }
                let resolved = try await Tests.resolve(at: directory, selection: .product(test))
                operations.append(.test(resolved.products))
            }
            if stage.publish != nil || defaults?.publish != nil {
                let when = try condition(stage.publish?.when ?? defaults?.publish?.when ?? "verified", allowed: [.always, .never, .verified])
                let publication = Publication(
                    guardCondition: when,
                    commit: stage.publish?.commit ?? defaults?.publish?.commit ?? false,
                    push: stage.publish?.push ?? defaults?.publish?.push ?? false,
                    message: stage.publish?.message ?? defaults?.publish?.message ?? "$message"
                )
                guard publication.message == "$message" || !publication.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw WorkflowConfigurationError.invalidPolicy("empty publish message")
                }
                operations.append(.publish(publication))
            }
            planned.append(Stage(id: stage.id, package: stage.package, directory: directory, needs: stage.needs ?? [], branch: branch, operations: operations))
        }
        if let startID {
            guard let first = planned.firstIndex(where: { $0.id == startID }) else {
                throw WorkflowConfigurationError.unknownStep(startID)
            }
            planned = Array(planned[first...])
        }
        return Plan(name: name, root: workspace.root, source: workspace.source,
                    requiresMessage: definition.inputs?.message == "required", stages: planned)
    }

    public static func present(_ plan: Plan) {
        print("Workflow: \(plan.name) [resolved plan; no operations performed]")
        print("Workspace: \(plan.root.path)")
        print("Configuration: \(plan.source.path)")
        for (index, stage) in plan.stages.enumerated() {
            print("\(index + 1). \(stage.id) [\(stage.package)] → \(stage.directory.path)")
            if !stage.needs.isEmpty { print("   needs: \(stage.needs.joined(separator: ", "))") }
            for operation in stage.operations { print("   • \(operation.description)") }
        }
        print("No workflow operations were executed.")
    }

    private static func condition(_ name: String, allowed: Set<Condition>) throws -> Condition {
        guard let value = Condition(rawValue: name), allowed.contains(value) else {
            throw WorkflowConfigurationError.invalidPolicy("when = \(name)")
        }
        return value
    }

    private static func validateNames(in configuration: WorkflowConfiguration) throws {
        for name in Array(configuration.packages.keys) + Array(configuration.workflows.keys) {
            guard validIdentifier(name) else { throw WorkflowConfigurationError.invalidName(name) }
        }
    }

    private static func validIdentifier(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        let start = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let remainder = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return start.contains(first) && text.unicodeScalars.dropFirst().allSatisfy(remainder.contains)
    }

    /// Reuse the workflow compiler's alias and containment rules for single-package actions.
    public static func packageDirectory(_ reference: String, in workspace: Workspace) throws -> URL {
        guard validIdentifier(reference) else {
            throw WorkflowConfigurationError.invalidName(reference)
        }
        guard let raw = workspace.configuration.packages[reference] else {
            throw WorkflowConfigurationError.missingPackage(reference)
        }
        return try packageURL(raw, in: workspace.root)
    }

    private static func packageURL(_ raw: String, in root: URL) throws -> URL {
        guard !raw.isEmpty, !raw.hasPrefix("/"), !raw.hasPrefix("~"), !raw.hasPrefix("$"),
              !raw.split(separator: "/").contains("..") else {
            throw WorkflowConfigurationError.invalidPackagePath(raw)
        }
        let destination = try PathResolver.resolveURL(
            raw, relativeTo: .directoryURL(root), terminalHint: .directory
        ).resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard destination == root || destination.path.hasPrefix(prefix) else {
            throw WorkflowConfigurationError.invalidPackagePath(raw)
        }
        var isDirectory: ObjCBool = false
        let manifest = destination.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue, FileManager.default.fileExists(atPath: manifest.path) else {
            throw WorkflowConfigurationError.missingPackageManifest(destination)
        }
        guard manifest.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == destination else {
            throw WorkflowConfigurationError.invalidPackagePath(manifest.path)
        }
        return destination
    }
}

