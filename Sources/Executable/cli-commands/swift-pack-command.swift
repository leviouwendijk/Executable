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

        @Flag(
            "test",
            short: "t",
            help: "After updating, run the Tests/ package's primary products; with --build, a failure stops the build and deploy."
        )
        public var test: Bool

        @Flag(
            "bench",
            help: "Run the Benchmarks/ package's primary products last (release)."
        )
        public var bench: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Run `swift package update` (default subcommand); then -t tests, -b builds, --bench benchmarks, in that order."
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

        let followUp = SwiftBuildFollowUp(
            test: options.test,
            bench: options.bench
        )

        try await followUp.before(
            at: directory
        )

        if options.build {
            let request = try SwiftBuildCommand.projectDefaultRequest(
                from: directory
            )

            let plan = try await Build.resolve(
                request
            )

            SwiftBuildCommand.present(
                plan
            )

            _ = try await Build.execute(
                plan
            )
        }

        try await followUp.after(
            at: directory
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
