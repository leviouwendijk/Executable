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
                "Write package.frame for the current directory, and Tests/ and Benchmarks/ package.frame files where those packages exist"
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

        let initialized = try PackageFrame.initialize(in: project)
        for file in [initialized.package, initialized.tests, initialized.benchmarks].compactMap({ $0 }) {
            print("Created \(file.path)")
        }
        if initialized.package == nil {
            print("\(project.appendingPathComponent(PackageFrame.fileName).path) already exists")
        }
    }
}
