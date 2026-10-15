import Foundation
import Parsers

/// Declarative workspace workflow. Parsers owns syntax and Codable decoding.
public struct WorkflowConfiguration: Decodable, Sendable {
    public let packages: [String: String]
    public let workflows: [String: Definition]

    public struct Definition: Decodable, Sendable {
        public let inputs: Inputs?
        public let defaults: Defaults?
        public let stages: [Stage]
    }

    public struct Inputs: Decodable, Sendable {
        public let message: String?
    }

    public struct Defaults: Decodable, Sendable {
        public let branch: String?
        public let configuration: String?
        public let onFailure: String?
        public let update: UpdatePolicy?
        public let publish: PublishPolicy?
    }

    public struct UpdatePolicy: Decodable, Sendable {
        public let when: String?
    }

    public struct PublishPolicy: Decodable, Sendable {
        public let when: String?
        public let commit: Bool?
        public let push: Bool?
        public let message: String?
    }

    public struct Stage: Decodable, Sendable {
        public let id: String
        public let package: String
        public let needs: [String]?
        public let test: String?
        public let update: UpdatePolicy?
        public let publish: PublishPolicy?
    }

    public static func parse(_ source: String) throws -> Self {
        let document = try Pkl.parse(source)
        try fields(document.entries, allowed: ["packages", "workflows"], at: "root")
        if let packages = document.entries.last(where: { $0.name == "packages" }) {
            _ = try block(packages)
        }
        if let workflows = document.entries.last(where: { $0.name == "workflows" }) {
            for workflow in try block(workflows) {
                let contents = try block(workflow)
                try fields(contents, allowed: ["inputs", "defaults", "stages"], at: workflow.name)
                for item in contents {
                    switch item.name {
                    case "inputs":
                        try fields(block(item), allowed: ["message"], at: "inputs")
                    case "defaults":
                        let defaults = try block(item)
                        try fields(defaults, allowed: ["branch", "configuration", "onFailure", "update", "publish"], at: "defaults")
                        try policies(defaults)
                    case "stages":
                        guard case .collection(let values) = item.value else {
                            throw WorkflowConfigurationError.malformed("stages in '\(workflow.name)' must be a list")
                        }
                        for value in values {
                            guard case .block(let stage) = value else {
                                throw WorkflowConfigurationError.malformed("stages entries must be records")
                            }
                            try fields(stage, allowed: ["id", "package", "needs", "test", "update", "publish"], at: "stage")
                            try policies(stage)
                        }
                    default: break
                    }
                }
            }
        }
        return try PklCoding(duplicateKeyStrategy: .reject).decode(Self.self, from: document)
    }

    private static func policies(_ entries: [Pkl.Entry]) throws {
        for entry in entries {
            switch entry.name {
            case "update": try fields(block(entry), allowed: ["when"], at: "update")
            case "publish": try fields(block(entry), allowed: ["when", "commit", "push", "message"], at: "publish")
            default: break
            }
        }
    }

    private static func block(_ entry: Pkl.Entry) throws -> [Pkl.Entry] {
        guard case .block(let items) = entry.value else {
            throw WorkflowConfigurationError.malformed("'\(entry.name)' must be a block")
        }
        return items
    }

    private static func fields(_ entries: [Pkl.Entry], allowed: Set<String>, at location: String) throws {
        for entry in entries where !allowed.contains(entry.name) {
            throw WorkflowConfigurationError.malformed("Unknown \(location) field '\(entry.name)'")
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
    case unknownStep(String)
    case repeatedStep(String)
    case unknownDependency(stage: String, prerequisite: String)
    case forwardDependency(stage: String, prerequisite: String)
    case invalidPolicy(String)
    case missingMessage
    case publishNotAuthorized
    case executionFromUnsupported

    public var errorDescription: String? {
        switch self {
        case .notFound(let path): return "Workspace configuration not found at \(path.path)"
        case .malformed(let detail): return "Invalid workflows.pkl: \(detail)"
        case .unknownWorkflow(let name): return "Unknown workflow '\(name)'."
        case .invalidName(let name): return "Invalid identifier '\(name)'."
        case .missingPackage(let name): return "No package alias '\(name)' is declared."
        case .invalidPackagePath(let path): return "Package path must remain inside workspace: '\(path)'."
        case .missingPackageManifest(let path): return "No Package.swift in \(path.path)."
        case .emptySteps(let name): return "Workflow '\(name)' has no stages."
        case .unknownStep(let name): return "No workflow stage has id '\(name)'."
        case .repeatedStep(let name): return "Duplicate workflow stage id '\(name)'."
        case .unknownDependency(let stage, let need): return "Stage '\(stage)' needs unknown stage '\(need)'."
        case .forwardDependency(let stage, let need): return "Stage '\(stage)' needs '\(need)', which must appear earlier."
        case .invalidPolicy(let value): return "Unsupported workflow policy: \(value)."
        case .missingMessage: return "Workflow publishing requires --message with a nonempty commit message."
        case .publishNotAuthorized: return "Publishing requires explicit --publish authorization."
        case .executionFromUnsupported: return "--from is planning-only until prior-stage verification can be established."
        }
    }
}

