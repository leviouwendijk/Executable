import Foundation
import Parsers

/// Workspace configuration, separate from each package's build-object.pkl.
public struct WorkflowConfiguration: Decodable, Sendable {
    public let packages: [String: String]
    public let workflows: [String: Definition]

    public struct Definition: Decodable, Sendable {
        public let steps: [Step]
    }

    public struct Step: Decodable, Sendable {
        public let package: String
        public let actions: [String]
    }

    public static func parse(_ source: String) throws -> Self {
        let document = try Pkl.parse(source)
        try requireFields(document.entries, allowed: ["packages", "workflows"], context: "root")
        if let workflows = document.entries.first(where: { $0.name == "workflows" }) {
            guard case .block(let definitions) = workflows.value else {
                throw WorkflowConfigurationError.malformed("workflows must be a block")
            }
            for definition in definitions {
                guard case .block(let fields) = definition.value else {
                    throw WorkflowConfigurationError.malformed("workflow '\(definition.name)' must be a block")
                }
                try requireFields(fields, allowed: ["steps"], context: definition.name)
                if let steps = fields.first(where: { $0.name == "steps" }) {
                    guard case .collection(let values) = steps.value else {
                        throw WorkflowConfigurationError.malformed("steps in '\(definition.name)' must be a list")
                    }
                    for value in values {
                        guard case .block(let fields) = value else {
                            throw WorkflowConfigurationError.malformed("each step in '\(definition.name)' must be a record")
                        }
                        try requireFields(fields, allowed: ["package", "actions"], context: "step")
                    }
                }
            }
        }
        return try PklCoding(duplicateKeyStrategy: .reject).decode(Self.self, from: document)
    }

    private static func requireFields(
        _ fields: [Pkl.Entry],
        allowed: Set<String>,
        context: String
    ) throws {
        for field in fields where !allowed.contains(field.name) {
            throw WorkflowConfigurationError.malformed("Unknown \(context) field '\(field.name)'")
        }
    }
}

public enum WorkflowConfigurationError: Error, LocalizedError, Sendable {
    case notFound(URL)
    case malformed(String)
    case unknownWorkflow(String)
    case invalidName(String)
    case missingPackage(String)
    case invalidPackagePath(String)
    case missingPackageManifest(URL)
    case emptySteps(String)
    case emptyActions(String)
    case unsupportedAction(String)
    case unknownStep(String)
    case repeatedStep(String)
    case readOnly

    public var errorDescription: String? {
        switch self {
        case .notFound(let path): return "Workspace configuration not found at \(path.path)"
        case .malformed(let description): return "Invalid workflows.pkl: \(description)"
        case .unknownWorkflow(let name): return "Unknown workflow '\(name)'."
        case .invalidName(let name): return "Invalid workflow or package alias '\(name)'."
        case .missingPackage(let name): return "No package alias '\(name)' is declared."
        case .invalidPackagePath(let path): return "Package path must remain inside the workspace: '\(path)'."
        case .missingPackageManifest(let path): return "No Package.swift in \(path.path)."
        case .emptySteps(let name): return "Workflow '\(name)' has no steps."
        case .emptyActions(let name): return "Workflow step '\(name)' has no actions."
        case .unsupportedAction(let action): return "Unsupported workflow action '\(action)'."
        case .unknownStep(let name): return "No workflow step uses package alias '\(name)'."
        case .repeatedStep(let name): return "Cannot use --from with repeated package alias '\(name)'."
        case .readOnly: return "Workflow execution is not available in Pass 6A. Supply --dry-run."
        }
    }
}
