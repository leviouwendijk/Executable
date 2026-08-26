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
}
