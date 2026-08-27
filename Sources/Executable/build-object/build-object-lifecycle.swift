import Foundation
import Version
import plate

public enum BuildObjectLifecycle {
    public enum Error:
        Swift.Error,
        Sendable,
        LocalizedError
    {
        case invalidObjectType(String)

        public var errorDescription: String? {
            switch self {
            case .invalidObjectType(let value):
                return "Invalid executable object type '\(value)'."
            }
        }
    }

    public struct InitializeRequest:
        Sendable,
        Codable,
        Hashable
    {
        public var name: String?
        public var types: [String]
        public var details: String
        public var author: String?
        public var update: String
        public var createCompiled: Bool

        public init(
            name: String? = nil,
            types: [String] = ["binary"],
            details: String = "",
            author: String? = nil,
            update: String = "",
            createCompiled: Bool = true
        ) {
            self.name = name
            self.types = types
            self.details = details
            self.author = author
            self.update = update
            self.createCompiled = createCompiled
        }
    }

    public struct InitializeResult: Sendable {
        public let configurationURL: URL
        public let compiledURL: URL
        public let createdConfiguration: Bool
        public let createdCompiled: Bool

        public init(
            configurationURL: URL,
            compiledURL: URL,
            createdConfiguration: Bool,
            createdCompiled: Bool
        ) {
            self.configurationURL = configurationURL.standardizedFileURL
            self.compiledURL = compiledURL.standardizedFileURL
            self.createdConfiguration = createdConfiguration
            self.createdCompiled = createdCompiled
        }
    }

    public struct ModernizeResult: Sendable {
        public let configurationURL: URL
        public let name: String
        public let modernized: Bool
        public let backupURL: URL?

        public init(
            configurationURL: URL,
            name: String,
            modernized: Bool,
            backupURL: URL?
        ) {
            self.configurationURL = configurationURL.standardizedFileURL
            self.name = name
            self.modernized = modernized
            self.backupURL = backupURL?.standardizedFileURL
        }
    }

    public static func initializeEmpty(
        at directory: URL
    ) throws -> InitializeResult {
        let configurationURL = directory
            .standardizedFileURL
            .appendingPathComponent(
                "build-object.pkl"
            )
        let compiledURL = directory
            .standardizedFileURL
            .appendingPathComponent(
                "compiled.pkl"
            )
        let fileManager = FileManager.default
        var createdConfiguration = false
        var createdCompiled = false

        if !fileManager.fileExists(
            atPath: configurationURL.path
        ) {
            try BuildObjectConfiguration.new(
                to: configurationURL
            )
            createdConfiguration = true
        }

        if !fileManager.fileExists(
            atPath: compiledURL.path
        ) {
            try CompiledLocalBuildObject.new(
                to: compiledURL
            )
            createdCompiled = true
        }

        return .init(
            configurationURL: configurationURL,
            compiledURL: compiledURL,
            createdConfiguration: createdConfiguration,
            createdCompiled: createdCompiled
        )
    }

    public static func initialize(
        at directory: URL,
        request: InitializeRequest
    ) throws -> InitializeResult {
        let directory = directory.standardizedFileURL
        let configurationURL = directory.appendingPathComponent(
            "build-object.pkl"
        )
        let compiledURL = directory.appendingPathComponent(
            "compiled.pkl"
        )
        let fileManager = FileManager.default
        var createdConfiguration = false
        var createdCompiled = false

        if !fileManager.fileExists(
            atPath: configurationURL.path
        ) {
            let objectTypes = try request.types.map { value in
                guard let type = ExecutableObjectType(
                    rawValue: value
                ) else {
                    throw Error.invalidObjectType(
                        value
                    )
                }

                return type
            }

            let configuration = BuildObjectConfiguration(
                name:
                    request.name?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .nonEmpty
                    ?? directory.lastPathComponent,
                types: objectTypes,
                versions: .init(
                    release: ObjectVersion.default_version(
                        for: .release
                    )
                ),
                compile: .init(
                    use: false,
                    arguments: []
                ),
                details: request.details,
                author:
                    request.author?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .nonEmpty
                    ?? NSUserName(),
                update: request.update
            )

            try configuration.write(
                to: configurationURL
            )
            createdConfiguration = true
        }

        if request.createCompiled,
           !fileManager.fileExists(
                atPath: compiledURL.path
           ) {
            try CompiledLocalBuildObject.new(
                to: compiledURL
            )
            createdCompiled = true
        }

        return .init(
            configurationURL: configurationURL,
            compiledURL: compiledURL,
            createdConfiguration: createdConfiguration,
            createdCompiled: createdCompiled
        )
    }

    public static func modernize(
        at directory: URL,
        backup: Bool = true
    ) throws -> ModernizeResult {
        let configurationURL =
            try BuildObjectConfiguration
                .traverseForBuildObjectPkl(
                    from: directory
                )
        let text = try String(
            contentsOf: configurationURL,
            encoding: .utf8
        )
        let parser = PklParser(
            text
        )

        if let modern = try? parser.parseBuildObject() {
            return .init(
                configurationURL: configurationURL,
                name: modern.name,
                modernized: false,
                backupURL: nil
            )
        }

        parser.reset()

        let legacy = try parser.parseLegacyBuildObject()
        let modern = legacy.modernize()
        let backupURL: URL?

        if backup {
            let candidate = configurationURL
                .deletingPathExtension()
                .appendingPathExtension(
                    "pkl.bak"
                )

            try FileManager.default.copyItem(
                at: configurationURL,
                to: candidate
            )
            backupURL = candidate
        } else {
            backupURL = nil
        }

        try modern.write(
            to: configurationURL
        )

        return .init(
            configurationURL: configurationURL,
            name: legacy.name,
            modernized: true,
            backupURL: backupURL
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
