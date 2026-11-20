import Arguments
import Foundation
import Interfaces
import Version

public enum SwiftReleaseCommand: RunnableArgumentCommand {
    public static let name = "release"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Release a given version: tag HEAD with it and push the tag"
            ),
            arg(
                "version",
                as: String.self,
                help: "The version to release: major.minor.patch (a leading v is accepted, never written)"
            ),
        ]
    }

    public enum CommandError: Error, LocalizedError {
        case invalidVersion(String)

        public var errorDescription: String? {
            switch self {
            case .invalidVersion(let text): return "'\(text)' is not a release version; use major.minor.patch."
            }
        }
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        let text = try invocation.require("version", as: String.self)
        guard let version = ReleaseTag.version(of: text) else {
            throw CommandError.invalidVersion(text)
        }
        let directory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        try await GitRepo.release(.exact(version), at: directory)
        print("Tagged \(ReleaseTag.name(for: version)) and pushed the tag.")
    }
}
