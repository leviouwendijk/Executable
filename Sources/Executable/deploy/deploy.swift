import Foundation
import Path

public enum Deploy {
    private static let maximumBuildProductAncestorDepth = 6

    public static func all(
        from projectDir: URL,
        config: Build.Config,
        to defaultDestination: URL
    ) async throws {
        try ensureDir(
            defaultDestination
        )

        let products = try await Products.executables(
            in: projectDir
        )

        for product in products {
            try moveOne(
                productName: product.name,
                from: projectDir,
                config: config,
                to: defaultDestination
            )
        }
    }

    public static func selected(
        from projectDir: URL,
        config: Build.Config,
        to defaultDestination: URL,
        products: [String],
        perProductDestinations: [String: URL] = [:]
    ) throws {
        try ensureDir(
            defaultDestination
        )

        for productName in products {
            let destination =
                perProductDestinations[productName]
                ?? defaultDestination

            try ensureDir(
                destination
            )

            try moveOne(
                productName: productName,
                from: projectDir,
                config: config,
                to: destination
            )
        }
    }

    @available(
        *,
        deprecated,
        message: """
        Executable deployment is product-based. \
        Use selected(..., products:perProductDestinations:).
        """
    )
    public static func selected(
        from projectDir: URL,
        config: Build.Config,
        to defaultDestination: URL,
        targets: [String],
        perTargetDestinations: [String: URL] = [:]
    ) throws {
        try selected(
            from: projectDir,
            config: config,
            to: defaultDestination,
            products: targets,
            perProductDestinations: perTargetDestinations
        )
    }

    private static func moveOne(
        productName: String,
        from projectDir: URL,
        config: Build.Config,
        to destinationRoot: URL
    ) throws {
        let sourceURL = resolvedBuildProductURL(
            productName: productName,
            from: projectDir,
            config: config
        )

        let destinationURL = destinationRoot
            .appendingPathComponent(
                productName
            )

        guard FileManager.default.fileExists(
            atPath: sourceURL.path
        ) else {
            throw DeployError.sourceMissing(
                sourceURL
            )
        }

        print("")

        print(
            "Deploying ".ansi(.brightBlack)
            + productName.ansi(.bold)
            + " → \(destinationRoot.path)"
                .ansi(.brightBlack)
        )

        let fileManager = FileManager.default
        let existed = fileManager.fileExists(
            atPath: destinationURL.path
        )

        do {
            if existed {
                print(
                    destinationURL.path
                        .ansi(
                            .brightBlack,
                            .bold
                        )
                    + " exists — replacing..."
                        .ansi(
                            .brightBlack
                        )
                )

                if let replaced = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: sourceURL
                ) {
                    print(
                        "Binary ".ansi(.brightBlack)
                        + "re".ansi(.brightBlack)
                        + "placed at ".ansi(.brightBlack)
                        + replaced.path.ansi(
                            .bold,
                            .brightBlack
                        )
                    )
                } else {
                    print(
                        """
                        Binary replaced, but no new URL was returned.
                        """
                        .ansi(.yellow)
                    )
                }
            } else {
                try fileManager.moveItem(
                    at: sourceURL,
                    to: destinationURL
                )

                print(
                    "Binary ".ansi(.brightBlack)
                    + "placed at ".ansi(.brightBlack)
                    + destinationURL.path.ansi(
                        .bold,
                        .brightBlack
                    )
                )
            }
        } catch {
            throw DeployError.replaceFailed(
                src: sourceURL,
                dst: destinationURL,
                underlying: error.localizedDescription
            )
        }

        do {
            try writeMetadata(
                for: productName,
                projectDir: projectDir,
                config: config,
                destinationRoot: destinationRoot
            )
        } catch {
            print(
                DeployError.metadataWriteFailed(
                    destinationRoot
                        .appendingPathComponent(
                            "\(productName).metadata"
                        ),
                    underlying: error.localizedDescription
                )
                .formatted()
            )
        }

        let banner =
            "\n        \(productName) "
                .ansi(.bold)
            + "is now an executable binary for "
            + projectDir.lastPathComponent
                .ansi(.italic)
            + "\n    "

        print(
            banner
        )
    }

    private static func resolvedBuildProductURL(
        productName: String,
        from projectDir: URL,
        config: Build.Config
    ) -> URL {
        let fallbackURL = buildProductURL(
            productName: productName,
            from: projectDir,
            config: config
        )

        guard let ancestor = PathAncestorSearch.nearestAncestor(
            startingAt: projectDir,
            treatingStartAsDirectory: true,
            includingStart: true,
            maxDepth: maximumBuildProductAncestorDepth,
            where: {
                candidate in

                FileManager.default.fileExists(
                    atPath: buildProductURL(
                        productName: productName,
                        from: candidate,
                        config: config
                    ).path
                )
            }
        ) else {
            return fallbackURL
        }

        return buildProductURL(
            productName: productName,
            from: ancestor,
            config: config
        )
    }

    private static func buildProductURL(
        productName: String,
        from projectDir: URL,
        config: Build.Config
    ) -> URL {
        projectDir
            .standardizedFileURL
            .appendingPathComponent(
                ".build",
                isDirectory: true
            )
            .appendingPathComponent(
                config.buildDirComponent,
                isDirectory: true
            )
            .appendingPathComponent(
                productName,
                isDirectory: false
            )
    }

    private static func ensureDir(
        _ directory: URL
    ) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DeployError.createDirectoryFailed(
                directory,
                underlying: error.localizedDescription
            )
        }
    }

    private static func writeMetadata(
        for productName: String,
        projectDir: URL,
        config: Build.Config,
        destinationRoot: URL
    ) throws {
        let metadataURL = destinationRoot
            .appendingPathComponent(
                "\(productName).metadata"
            )

        let content = """
        ProjectRootPath=\(projectDir.path)
        BuildType=\(config.buildDirComponent)
        DeployedAt=\(ISO8601DateFormatter().string(from: Date()))
        DestinationRoot=\(destinationRoot.path)
        """

        try content.write(
            to: metadataURL,
            atomically: true,
            encoding: .utf8
        )

        print(
            "Metadata written: ".ansi(
                .brightBlack
            )
            + metadataURL.path.ansi(
                .brightBlack,
                .bold
            )
        )
    }
}
