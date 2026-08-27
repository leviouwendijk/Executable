import Foundation
import Interfaces
import Version
import plate

public enum ExecutableVersion {
    public struct Snapshot: Sendable {
        public let configurationURL: URL
        public let compiledURL: URL
        public let name: String
        public let types: [String]
        public let compiled: ObjectVersion
        public let release: ObjectVersion
        public let ahead: Int?
        public let behind: Int?

        public init(
            configurationURL: URL,
            compiledURL: URL,
            name: String,
            types: [String],
            compiled: ObjectVersion,
            release: ObjectVersion,
            ahead: Int?,
            behind: Int?
        ) {
            self.configurationURL = configurationURL.standardizedFileURL
            self.compiledURL = compiledURL.standardizedFileURL
            self.name = name
            self.types = types
            self.compiled = compiled
            self.release = release
            self.ahead = ahead
            self.behind = behind
        }
    }

    public struct IncrementResult: Sendable {
        public let configurationURL: URL
        public let before: ObjectVersion
        public let after: ObjectVersion
        public let level: ObjectVersionLevel

        public init(
            configurationURL: URL,
            before: ObjectVersion,
            after: ObjectVersion,
            level: ObjectVersionLevel
        ) {
            self.configurationURL = configurationURL.standardizedFileURL
            self.before = before
            self.after = after
            self.level = level
        }
    }

    public static func inspect(
        at directory: URL
    ) async throws -> Snapshot {
        let configurationURL =
            try BuildObjectConfiguration
                .traverseForBuildObjectPkl(
                    from: directory
                )
        let configuration = try BuildObjectConfiguration(
            from: configurationURL
        )

        let compiledURL =
            try CompiledLocalBuildObject
                .traverseForCompiledObjectPkl(
                    from: directory
                )
        let compiled = try CompiledLocalBuildObject(
            from: compiledURL
        )

        let divergence = try? await GitRepo.divergence(
            configurationURL.deletingLastPathComponent()
        )

        return .init(
            configurationURL: configurationURL,
            compiledURL: compiledURL,
            name: configuration.name,
            types: configuration.types.map(\.rawValue),
            compiled: compiled.version,
            release: configuration.versions.release,
            ahead: divergence?.ahead,
            behind: divergence?.behind
        )
    }

    public static func incrementRelease(
        at directory: URL,
        level: ObjectVersionLevel
    ) throws -> IncrementResult {
        let configurationURL =
            try BuildObjectConfiguration
                .traverseForBuildObjectPkl(
                    from: directory
                )

        var configuration = try BuildObjectConfiguration(
            from: configurationURL
        )
        let before = configuration.versions.release

        configuration.versions.release.increment(
            level
        )

        let updated = BuildObjectConfiguration(
            uuid: configuration.uuid,
            name: configuration.name,
            types: configuration.types,
            versions: configuration.versions,
            compile: configuration.compile,
            details: configuration.details,
            author: configuration.author,
            update: configuration.update
        )

        try updated.write(
            to: configurationURL
        )

        return .init(
            configurationURL: configurationURL,
            before: before,
            after: updated.versions.release,
            level: level
        )
    }
}
