import Arguments
import Foundation
import Version
import Interfaces

public enum SwiftIncrementCommand: RunnableArgumentCommand {
    public static let name = "increment"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Release the next version: tag HEAD with it and push the tag"
            ),
            arg(
                "level",
                as: ObjectVersionLevel.self,
                help: "Level to bump: major | minor | patch"
            ),
        ]
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        let level = try invocation.require(
            "level",
            as: ObjectVersionLevel.self
        )
        let directory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        guard try PackageFrame.package(in: directory) != nil else {
            if let legacy = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: directory) {
                throw ConfigurationFileError.legacy(legacy)
            }
            throw BuildObjectDiscoveryError.notFound(filename: PackageFrame.fileName, maxDepth: 1, startURL: directory)
        }

        let result = try await GitRepo.release(.next(level), at: directory)
        print(
            "Tagged \(ReleaseTag.name(for: result.to)) (was \(result.from.map(ReleaseTag.name(for:)) ?? "untagged")) and pushed the tag."
        )
    }
}
