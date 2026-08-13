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

        let args = buildArguments(
            packageName: packageName,
            config: config
        )

        _ = try await runSwift(
            args,
            in: dir
        )

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

        let contents = (
            try? fileManager.contentsOfDirectory(
                atPath: builtDir.path
            )
        ) ?? []

        for item in contents {
            guard suffixes.contains(
                where: {
                    item.hasSuffix(
                        $0
                    )
                }
            ) else {
                continue
            }

            let source = builtDir.appendingPathComponent(
                item
            )

            let destination = outDir.appendingPathComponent(
                item
            )

            if fileManager.fileExists(
                atPath: destination.path
            ) {
                try? fileManager.removeItem(
                    at: destination
                )
            }

            do {
                try fileManager.copyItem(
                    at: source,
                    to: destination
                )
            } catch {
            }
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

    package static func buildArguments(
        packageName: String,
        config: Build.Config
    ) -> [String] {
        [
            "build",
            "-c",
            config.buildDirComponent,

            "-Xswiftc",
            "-enable-library-evolution",

            "-Xswiftc",
            "-emit-module-interface-path",

            "-Xswiftc",
            ".build/\(config.buildDirComponent)/Modules/\(packageName).swiftinterface",

            "-Xswiftc",
            "-emit-library",

            "-Xswiftc",
            "-emit-module",
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
