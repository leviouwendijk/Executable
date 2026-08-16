import Foundation
import Interfaces

public enum Products {
    public static func executables(
        in packageDir: URL
    ) async throws -> [ExecutableProduct] {
        let data = try await SwiftPackageDumpInvocation.data(
            in: packageDir
        )

        let blob = SwiftPackageDumpBlob(
            raw: data
        )

        let reader = try SwiftPackageDumpReader(
            blob: blob
        )

        let explicitProducts = reader
            .allProducts()
            .compactMap {
                product -> ExecutableProduct? in

                guard
                    let type = try? product["type"]?.objectValue,
                    type["executable"] != nil,
                    let name = try? product["name"]?.stringValue,
                    let targetValues = try? product["targets"]?.arrayValue
                else {
                    return nil
                }

                let targets = targetValues.compactMap {
                    try? $0.stringValue
                }

                return .init(
                    name: name,
                    targets: targets
                )
            }

        let explicitlyCoveredTargets = Set(
            explicitProducts.flatMap(
                \.targets
            )
        )

        let implicitProducts = reader
            .executableTargetNames()
            .filter {
                !explicitlyCoveredTargets.contains(
                    $0
                )
            }
            .map {
                targetName in

                ExecutableProduct(
                    name: targetName,
                    targets: [
                        targetName,
                    ]
                )
            }

        let products =
            explicitProducts
            + implicitProducts

        guard !products.isEmpty else {
            throw ProductsError.noExecutableProductsFound
        }

        return products
    }

    public static func executableNames(
        in packageDir: URL
    ) async throws -> [String] {
        try await executables(
            in: packageDir
        )
        .map(\.name)
    }
}
