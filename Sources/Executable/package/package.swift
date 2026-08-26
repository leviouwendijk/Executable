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

    public static func name(
        at directory: URL
    ) async throws -> String {
        let data = try await SwiftPackageDumpInvocation.data(
            in: directory
        )

        let reader = try SwiftPackageDumpReader(
            blob: SwiftPackageDumpBlob(
                raw: data
            )
        )

        return reader.packageName()
            ?? directory.lastPathComponent
    }
}
