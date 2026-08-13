import Foundation
import Interfaces

public enum BuildLibrary {
    public struct Output:
        Sendable
    {
        public let packageName: String
        public let artifactsDir: URL
        public let builtDir: URL
    }

    public static func buildAndExport(
        at dir: URL,
        config: Build.Config,
        local: Bool,
        modulesRoot: URL
    ) async throws -> Output {
        let packageName = try await packageInfo(
            dir
        )

        let libraryProducts = try await libraryProducts(
            dir
        )

        guard !libraryProducts.isEmpty else {
            throw BuildError.invocationFailed(
                message: "No library products found in package."
            )
        }

        let libraryTargets = Array(
            Set(
                libraryProducts.flatMap(
                    \.targets
                )
            )
        )
        .sorted()

        guard !libraryTargets.isEmpty else {
            throw BuildError.invocationFailed(
                message: "Library products contain no targets."
            )
        }

        for targetName in libraryTargets {
            _ = try await runSwift(
                buildArguments(
                    targetName: targetName,
                    config: config
                ),
                in: dir
            )
        }

        let builtDir = dir.appendingPathComponent(
            ".build/\(config.buildDirComponent)"
        )

        if local {
            return .init(
                packageName: packageName,
                artifactsDir: builtDir,
                builtDir: builtDir
            )
        }

        let outDir = modulesRoot.appendingPathComponent(
            packageName,
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: outDir,
            withIntermediateDirectories: true
        )

        let artifacts = try artifactURLs(
            in: builtDir
        )

        guard !artifacts.isEmpty else {
            throw BuildError.invocationFailed(
                message: "No distributable library artifacts were produced."
            )
        }

        let fileManager = FileManager.default

        for source in artifacts {
            let destination = outDir.appendingPathComponent(
                source.lastPathComponent
            )

            if fileManager.fileExists(
                atPath: destination.path
            ) {
                try fileManager.removeItem(
                    at: destination
                )
            }

            try fileManager.copyItem(
                at: source,
                to: destination
            )
        }

        print(
            "Library artifacts exported to \(outDir.path)"
                .ansi(
                    .green
                )
        )

        return .init(
            packageName: packageName,
            artifactsDir: outDir,
            builtDir: builtDir
        )
    }

    package static func packageInfo(
        _ dir: URL
    ) async throws -> String {
        let data = try await SwiftPackageDumpInvocation.data(
            in: dir
        )

        let blob = SwiftPackageDumpBlob(
            raw: data
        )

        let reader = try SwiftPackageDumpReader(
            blob: blob
        )

        return reader.packageName()
            ?? dir.lastPathComponent
    }

    package struct LibraryProduct:
        Sendable,
        Equatable
    {
        package let name: String
        package let targets: [String]

        package init(
            name: String,
            targets: [String]
        ) {
            self.name = name
            self.targets = targets
        }
    }

    package static func libraryProducts(
        _ dir: URL
    ) async throws -> [LibraryProduct] {
        let data = try await SwiftPackageDumpInvocation.data(
            in: dir
        )

        let blob = SwiftPackageDumpBlob(
            raw: data
        )

        let reader = try SwiftPackageDumpReader(
            blob: blob
        )

        return reader.allProducts().compactMap {
            product -> LibraryProduct? in

            guard
                let type = try? product["type"]?.objectValue,
                type["library"] != nil,
                let name = try? product["name"]?.stringValue,
                let targetValues = try? product["targets"]?.arrayValue
            else {
                return nil
            }

            let targets = targetValues.compactMap {
                try? $0.stringValue
            }

            return LibraryProduct(
                name: name,
                targets: targets
            )
        }
    }

    package static func artifactURLs(
        in builtDir: URL
    ) throws -> [URL] {
        let suffixes = [
            ".swiftmodule",
            ".swiftdoc",
            ".swiftinterface",
            ".swiftsourceinfo",
            ".abi.json",
            ".dylib",
            ".a",
        ]

        let fileManager = FileManager.default

        let roots = [
            builtDir,
            builtDir.appendingPathComponent(
                "Modules",
                isDirectory: true
            ),
        ]

        var artifacts: [URL] = []

        for root in roots {
            var isDirectory: ObjCBool = false

            guard
                fileManager.fileExists(
                    atPath: root.path,
                    isDirectory: &isDirectory
                ),
                isDirectory.boolValue
            else {
                continue
            }

            let contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [
                    .skipsHiddenFiles,
                ]
            )

            artifacts.append(
                contentsOf: contents.filter { artifact in
                    suffixes.contains { suffix in
                        artifact.lastPathComponent.hasSuffix(
                            suffix
                        )
                    }
                }
            )
        }

        return artifacts.sorted {
            $0.path < $1.path
        }
    }

    package static func buildArguments(
        targetName: String,
        config: Build.Config
    ) -> [String] {
        [
            "build",
            "-c",
            config.buildDirComponent,

            "--target",
            targetName,

            "--enable-parseable-module-interfaces",

            "-Xswiftc",
            "-enable-library-evolution",
        ]
    }

    @discardableResult
    package static func runSwift(
        _ command: [String],
        in dir: URL
    ) async throws -> Build.BuildResult {
        try await Build.runSwift(
            command: command,
            in: dir
        )
    }
}
