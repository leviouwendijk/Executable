import Foundation

public enum Products {
    public static func executables(
        in packageDir: URL
    ) async throws -> [ExecutableProduct] {
        let manifest = try await Package.manifest(
            at: packageDir
        )

        return try executables(
            in: manifest
        )
    }

    public static func executables(
        in manifest: SwiftPackageManifest
    ) throws -> [ExecutableProduct] {
        let explicitProducts = manifest.products
            .filter {
                $0.kind == .executable
            }
            .map {
                ExecutableProduct(
                    name: $0.name,
                    targets: $0.targets
                )
            }

        let explicitlyCoveredTargets = Set(
            explicitProducts.flatMap(
                \.targets
            )
        )

        let implicitProducts = manifest.targets
            .filter {
                $0.type == "executable"
            }
            .map(\.name)
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

    public static func executableNames(
        in manifest: SwiftPackageManifest
    ) throws -> [String] {
        try executables(
            in: manifest
        )
        .map(\.name)
    }
}
