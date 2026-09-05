import Foundation

public enum Package {
    public typealias Result = Resolve.Result

    @discardableResult
    public static func update(
        at directory: URL
    ) async throws -> Result {
        try await Resolve.get(
            at: directory
        )
    }

    @discardableResult
    public static func resolve(
        at directory: URL
    ) async throws -> Result {
        try await Resolve.resolve(
            at: directory
        )
    }

    /// Read declaration semantics from `swift package dump-package`.
    public static func manifest(
        at directory: URL
    ) async throws -> SwiftPackageManifest {
        let data = try await SwiftPackageDumpInvocation.data(
            in: directory
        )

        return try SwiftPackageManifest(
            dump: data,
            fallbackName:
                directory.lastPathComponent
        )
    }

    /// Resolve SwiftPM package topology while retaining the root manifest as
    /// separate declaration truth.
    ///
    /// `show-dependencies` may perform normal SwiftPM resolution/preparation and
    /// therefore may create package workspace state beneath the package root.
    public static func graph(
        at directory: URL
    ) async throws -> SwiftPackageGraph {
        let manifest = try await manifest(
            at: directory
        )

        let data = try await SwiftPackageDependencyGraphInvocation.data(
            in: directory
        )

        do {
            return try SwiftPackageGraph(
                dependencyData: data,
                manifest: manifest
            )
        } catch let error as SwiftPackageGraphError {
            throw error
        } catch {
            throw SwiftPackageGraphError.decodeFailed(
                message: String(
                    describing: error
                )
            )
        }
    }

    public static func name(
        at directory: URL
    ) async throws -> String {
        try await manifest(
            at: directory
        )
        .name
    }
}
