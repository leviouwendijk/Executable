import Arguments
import Foundation

public enum SwiftConfigCommand: ArgumentCommand {
    public static let name = "config"

    public static let children: [ArgumentCommandType] = [
        SwiftConfigInitCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Manage package.frame"
            ),
        ]
    }
}

public enum SwiftConfigInitCommand: RunnableArgumentCommand {
    public static let name = "init"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Write package.frame for the current directory, and Tests/package.frame when Tests/Package.swift exists"
            ),
        ]
    }

    public static func run(
        _ invocation: ParsedInvocation
    ) async throws {
        _ = invocation
        let project = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL

        if let legacy = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: project),
           try BuildObjectDiscovery.local(named: PackageFrame.fileName, in: project) == nil {
            throw ConfigurationFileError.legacy(legacy)
        }

        try write(PackageFrame.source(PackageConfiguration()), in: project)

        let tests = project.appendingPathComponent(Tests.conventionalDirectory, isDirectory: true)
        if try BuildObjectDiscovery.local(named: "Package.swift", in: tests) != nil {
            try write(PackageFrame.source(TestConfiguration()), in: tests)
        }
    }
}

private extension SwiftConfigInitCommand {
    static func write(
        _ source: String,
        in directory: URL
    ) throws {
        let file = directory.appendingPathComponent(PackageFrame.fileName)
        if try BuildObjectDiscovery.local(named: PackageFrame.fileName, in: directory) != nil {
            print("\(file.path) already exists")
            return
        }
        try BuildObjectDiscovery.requireOwned(file, by: directory)
        try BuildObjectFile.write(source, to: file)
        print("Created \(file.path)")
    }
}
