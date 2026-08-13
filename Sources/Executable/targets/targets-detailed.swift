import Foundation
import Interfaces

public enum ExecutableRole:
    String,
    Sendable
{
    case cli
    case app
    case other
}

public struct ExecutableTarget:
    Sendable
{
    public let name: String
    public let path: String?
    public let role: ExecutableRole
}

public enum TargetsDetailed {
    public static func list(
        in packageDir: URL
    ) async throws -> [ExecutableTarget] {
        let data = try await SwiftPackageDumpInvocation.data(
            in: packageDir
        )

        let blob = SwiftPackageDumpBlob(
            raw: data
        )

        let reader = try SwiftPackageDumpReader(
            blob: blob
        )

        let rawTargets = reader.allTargets()

        let executables = rawTargets.compactMap {
            dictionary -> ExecutableTarget? in

            guard
                (try? dictionary["type"]?.stringValue)
                    == "executable",
                let name = try? dictionary["name"]?.stringValue
            else {
                return nil
            }

            let path = try? dictionary["path"]?.stringValue

            return .init(
                name: name,
                path: path,
                role: guessRole(
                    name: name,
                    path: path
                )
            )
        }

        if executables.isEmpty {
            throw TargetsError.noExecutablesFound
        }

        return executables
    }

    private static func guessRole(
        name: String,
        path: String?
    ) -> ExecutableRole {
        let searchable = (
            name
            + " "
            + (path ?? "")
        )
        .lowercased()

        if
            searchable.contains("cli")
            || searchable.contains("tool")
            || searchable.contains("cmd")
        {
            return .cli
        }

        if
            searchable.contains("app")
            || searchable.contains("application")
        {
            return .app
        }

        return .other
    }
}
