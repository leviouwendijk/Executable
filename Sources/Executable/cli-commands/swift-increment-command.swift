import Arguments
import Foundation
import Version

public enum SwiftIncrementCommand: RunnableArgumentCommand {
    public static let name = "increment"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Increment the project version"
            ),
            opt(
                "target",
                short: "t",
                as: VersionReference.self,
                default: .release,
                help: "Which version to bump: release (default) or compiled"
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
        let target = try invocation.value(
            "target",
            as: VersionReference.self,
            default: .release
        )

        let level = try invocation.require(
            "level",
            as: ObjectVersionLevel.self
        )

        switch target {
        case .release:
            let result = try ExecutableVersion.incrementRelease(
                at: URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath,
                    isDirectory: true
                ),
                level: level
            )

            print(
                "Updated \(target.rawValue) → \(result.after.string(prefixStyle: .short))"
            )

        case .compiled:
            print(
                "Do not manually increment compiled object, build in order to do so."
            )
        }
    }
}
