import Arguments
import Foundation

public enum SwiftPackCommand: ArgumentCommand {
    public static let name = "pack"
    public static let defaultChild = SwiftPackGetCommand.self

    public static let children: [ArgumentCommandType] = [
        SwiftPackGetCommand.self,
        SwiftPackResolveCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "SwiftPM dependency operations (update/resolve)."
            ),
        ]
    }
}

public enum SwiftPackGetCommand: BoundArgumentCommand {
    public static let name = "get"

    public struct Options: ArgumentGroup {
        @Opt(
            "dir",
            short: "d",
            help: "Package directory (default: current directory)."
        )
        public var directory: String?

        @Flag(
            "build",
            short: "b",
            help: "After updating dependencies, run the normal project-default build workflow."
        )
        public var build: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Run `swift package update` (default subcommand)."
            ),
            try params(
                Options.self
            ),
        ]
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let directory = packageDirectory(
            options.directory
        )

        _ = try await Package.update(
            at: directory
        )

        guard options.build else {
            return
        }

        let request = try SwiftBuildCommand.projectDefaultRequest(
            from: directory
        )

        let plan = try await Build.resolve(
            request
        )

        _ = try await Build.execute(
            plan
        )
    }
}

public enum SwiftPackResolveCommand: BoundArgumentCommand {
    public static let name = "resolve"

    public struct Options: ArgumentGroup {
        @Opt(
            "dir",
            short: "d",
            help: "Package directory (default: current directory)."
        )
        public var directory: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Run `swift package resolve`."
            ),
            try params(
                Options.self
            ),
        ]
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        _ = try await Package.resolve(
            at: packageDirectory(
                options.directory
            )
        )
    }
}

private func packageDirectory(
    _ path: String?
) -> URL {
    path.map {
        URL(
            fileURLWithPath: $0,
            isDirectory: true
        )
    } ?? URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
}
