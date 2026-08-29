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

    public static func manifest(
        at directory: URL
    ) async throws -> SwiftPackageManifest {
        let data = try await SwiftPackageDumpInvocation.data(
            in: directory
        )

        return try SwiftPackageManifest(
            dump: data,
            fallbackName: directory.lastPathComponent
        )
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
