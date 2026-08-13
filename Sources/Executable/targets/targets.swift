import Foundation
import Interfaces

public enum Targets {
    public static func executableNames(
        in packageDir: URL
    ) async throws -> [String] {
        let data = try await SwiftPackageDumpInvocation.data(
            in: packageDir
        )

        let blob = SwiftPackageDumpBlob(
            raw: data
        )

        let reader = try SwiftPackageDumpReader(
            blob: blob
        )

        let names = reader.executableTargetNames()

        if names.isEmpty {
            throw TargetsError.noExecutablesFound
        }

        return names
    }
}
