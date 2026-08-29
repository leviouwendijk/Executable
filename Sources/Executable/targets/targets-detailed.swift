import Foundation

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
        let manifest = try await Package.manifest(
            at: packageDir
        )

        return try list(
            in: manifest
        )
    }

    public static func list(
        in manifest: SwiftPackageManifest
    ) throws -> [ExecutableTarget] {
        let executables = manifest.targets
            .filter {
                $0.type == "executable"
            }
            .map { target in
                ExecutableTarget(
                    name: target.name,
                    path: target.path,
                    role: guessRole(
                        name: target.name,
                        path: target.path
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
