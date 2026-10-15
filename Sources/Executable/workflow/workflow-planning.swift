import Foundation
import Path

/// Resolves paths and test products, but deliberately cannot execute actions.
public enum WorkflowPlanning {
    public struct Workspace: Sendable {
        public let root: URL
        public let source: URL
        public let configuration: WorkflowConfiguration
    }

    public enum Action: Sendable, Equatable {
        case update
        case build
        case test([String])
        case commit
        case push

        public var description: String {
            switch self {
            case .update: return "update"
            case .build: return "build"
            case .test(let products): return "test: " + products.joined(separator: ", ")
            case .commit: return "commit [not executed]"
            case .push: return "push [not executed]"
            }
        }
    }

    public struct Step: Sendable {
        public let package: String
        public let directory: URL
        public let actions: [Action]
    }

    public struct Plan: Sendable {
        public let name: String
        public let root: URL
        public let source: URL
        public let steps: [Step]
    }

    public static func discover(startingAt start: URL) throws -> Workspace {
        guard let root = PathAncestorSearch.nearestAncestorContainingAny(
            [".sbm/workflows.pkl"],
            startingAt: start
        ) else {
            throw WorkflowConfigurationError.notFound(start.appendingPathComponent(".sbm/workflows.pkl"))
        }
        return try load(root: root)
    }

    public static func load(root: URL) throws -> Workspace {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let source = canonical.appendingPathComponent(".sbm/workflows.pkl")
        // Reject symbolic links in .sbm or workflows.pkl: the file must belong to the chosen root.
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
        from startAlias: String? = nil
    ) async throws -> Plan {
        guard let definition = workspace.configuration.workflows[name] else {
            throw WorkflowConfigurationError.unknownWorkflow(name)
        }
        guard !definition.steps.isEmpty else { throw WorkflowConfigurationError.emptySteps(name) }
        try validateNames(in: workspace.configuration)
        let definitions: [WorkflowConfiguration.Step]
        if let startAlias {
            let matches = definition.steps.indices.filter { definition.steps[$0].package == startAlias }
            guard let first = matches.first else { throw WorkflowConfigurationError.unknownStep(startAlias) }
            guard matches.count == 1 else { throw WorkflowConfigurationError.repeatedStep(startAlias) }
            definitions = Array(definition.steps[first...])
        } else {
            definitions = definition.steps
        }
        var planned: [Step] = []
        for step in definitions {
            guard let rawPath = workspace.configuration.packages[step.package] else {
                throw WorkflowConfigurationError.missingPackage(step.package)
            }
            let directory = try packageURL(rawPath, in: workspace.root)
            guard !step.actions.isEmpty else {
                throw WorkflowConfigurationError.emptyActions(step.package)
            }
            var actions: [Action] = []
            for token in step.actions {
                let action: Action
                switch token {
                case "update": action = .update
                case "build": action = .build
                case "commit": action = .commit
                case "push": action = .push
                default:
                    guard token == "test" || token.hasPrefix("test:") else {
                        throw WorkflowConfigurationError.unsupportedAction(token)
                    }
                    let selection = try testSelection(token)
                    let testPlan = try await Tests.resolve(at: directory, selection: selection)
                    action = .test(testPlan.products)
                }
                actions.append(action)
            }
            planned.append(Step(package: step.package, directory: directory, actions: actions))
        }
        return Plan(name: name, root: workspace.root, source: workspace.source, steps: planned)
    }

    public static func present(_ plan: Plan) {
        print("Workflow: \(plan.name) [dry-run only]")
        print("Workspace: \(plan.root.path)")
        print("Configuration: \(plan.source.path)")
        for (index, step) in plan.steps.enumerated() {
            print("\(index + 1). \(step.package) → \(step.directory.path)")
            for action in step.actions { print("   • \(action.description)") }
        }
        print("No workflow actions were executed.")
    }

    private static func validateNames(in configuration: WorkflowConfiguration) throws {
        for name in Array(configuration.packages.keys) + Array(configuration.workflows.keys) {
            guard validIdentifier(name) else { throw WorkflowConfigurationError.invalidName(name) }
        }
    }

    private static func validIdentifier(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        let start = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let remaining = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return start.contains(first) && text.unicodeScalars.dropFirst().allSatisfy(remaining.contains)
    }

    private static func packageURL(_ rawPath: String, in root: URL) throws -> URL {
        guard !rawPath.isEmpty,
              !rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("~"),
              !rawPath.hasPrefix("$"),
              !rawPath.split(separator: "/").contains("..") else {
            throw WorkflowConfigurationError.invalidPackagePath(rawPath)
        }
        let destination = try PathResolver.resolveURL(
            rawPath,
            relativeTo: .directoryURL(root),
            terminalHint: .directory
        ).resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard destination == root || destination.path.hasPrefix(prefix) else {
            throw WorkflowConfigurationError.invalidPackagePath(rawPath)
        }
        var isDirectory: ObjCBool = false
        let manifest = destination.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: manifest.path) else {
            throw WorkflowConfigurationError.missingPackageManifest(destination)
        }
        // A manifest cannot redirect outside its resolved package directory.
        guard manifest.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == destination else {
            throw WorkflowConfigurationError.invalidPackagePath(manifest.path)
        }
        return destination
    }

    private static func testSelection(_ token: String) throws -> TestConfiguration.Selection {
        if token == "test" { return .primary }
        if token == "test:all" { return .all }
        let components = token.split(separator: ":", omittingEmptySubsequences: false)
        if components.count == 3, components[0] == "test", !components[2].isEmpty {
            switch components[1] {
            case "group": return .group(String(components[2]))
            case "product": return .product(String(components[2]))
            default: break
            }
        }
        throw WorkflowConfigurationError.unsupportedAction(token)
    }
}
