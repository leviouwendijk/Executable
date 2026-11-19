import Arguments
import Foundation
import Version

public enum SwiftIncrementCommand: RunnableArgumentCommand {
    public static let name = "increment"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Release the next version: for a package.frame project, tag HEAD and push the tag; for build-object.pkl, bump the file"
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

        let directory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        if try PackageFrame.package(in: directory) != nil {
            guard target == .release else {
                print("package.frame projects keep no compiled version; a deploy records what was built.")
                return
            }
            let result = try await ReleaseTags.increment(level, at: directory)
            print(
                "Tagged \(ReleaseTags.name(for: result.to)) (was \(result.from.map(ReleaseTags.name(for:)) ?? "untagged")) and pushed the tag."
            )
            return
        }

        switch target {
        case .release:
            let result = try ExecutableVersion.incrementRelease(
                at: directory,
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
