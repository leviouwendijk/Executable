import Foundation

public enum Targets {
    public static func executableNames(
        in packageDir: URL
    ) async throws -> [String] {
        let manifest = try await Package.manifest(
            at: packageDir
        )

        return try executableNames(
            in: manifest
        )
    }

    public static func executableNames(
        in manifest: SwiftPackageManifest
    ) throws -> [String] {
        let names = manifest.targets
            .filter {
                $0.type == "executable"
            }
            .map(\.name)

        if names.isEmpty {
            throw TargetsError.noExecutablesFound
        }

        return names
    }
}
