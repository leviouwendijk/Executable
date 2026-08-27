import Arguments
import Foundation
import plate

public enum SwiftVersionBumpTarget:
    String,
    Sendable,
    CaseIterable,
    ArgumentValue
{
    case release
    case compiled
}

public enum SwiftVersionBumpLevel:
    String,
    Sendable,
    CaseIterable,
    ArgumentValue
{
    case major
    case minor
    case patch
}

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
                as: SwiftVersionBumpTarget.self,
                default: .release,
                help: "Which version to bump: release (default) or compiled"
            ),
            arg(
                "level",
                as: SwiftVersionBumpLevel.self,
                help: "Level to bump: major | minor | patch"
            ),
        ]
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        let target = try invocation.value(
            "target",
            as: SwiftVersionBumpTarget.self,
            default: .release
        )

        let level = try invocation.require(
            "level",
            as: SwiftVersionBumpLevel.self
        )

        let objectURL = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        )

        var object = try BuildObjectConfiguration(
            from: objectURL
        )

        switch target {
        case .release:
            let current = object.versions.release

            switch level {
            case .major:
                object.versions.release = .init(
                    major: current.major + 1,
                    minor: 0,
                    patch: 0
                )

            case .minor:
                object.versions.release = .init(
                    major: current.major,
                    minor: current.minor + 1,
                    patch: 0
                )

            case .patch:
                object.versions.release = .init(
                    major: current.major,
                    minor: current.minor,
                    patch: current.patch + 1
                )
            }

            let configuration = BuildObjectConfiguration(
                uuid: object.uuid,
                name: object.name,
                types: object.types,
                versions: object.versions,
                compile: object.compile,
                details: object.details,
                author: object.author,
                update: object.update
            )

            try configuration.write(
                to: objectURL
            )

            print(
                "Updated \(target.rawValue) → \(object.versions.release.string(prefixStyle: .short))"
            )

        case .compiled:
            print(
                "Do not manually increment compiled object, build in order to do so."
            )
        }
    }
}
