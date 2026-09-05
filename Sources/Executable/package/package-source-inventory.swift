import Foundation

public extension Package {
    /// Ask SwiftPM for the exact root-package target/source inventory.
    ///
    /// This operation complements `manifest(at:)` and `graph(at:)`:
    ///
    /// - `manifest(at:)` reports declaration semantics.
    /// - `graph(at:)` reports resolved package dependency topology.
    /// - `sourceInventory(at:)` reports SwiftPM-resolved target source files.
    static func sourceInventory(
        at directory: URL
    ) async throws -> SwiftPackageSourceInventory {
        let data = try await SwiftPackageDescriptionInvocation.data(
            in: directory
        )

        do {
            return try SwiftPackageSourceInventory(
                descriptionData: data,
                packageDirectory: directory
            )
        } catch let error as SwiftPackageSourceInventoryError {
            throw error
        } catch {
            throw SwiftPackageSourceInventoryError.decodeFailed(
                message: String(
                    describing: error
                )
            )
        }
    }
}
