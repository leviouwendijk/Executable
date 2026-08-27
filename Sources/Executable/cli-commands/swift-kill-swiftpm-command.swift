import Arguments
import Foundation
import Terminal

public enum SwiftKillSwiftPMCommand: BoundArgumentCommand {
    public static let name = "kill-swiftpm"
    public static let aliases = [
        "kill",
        "killswift",
    ]

    public struct Options: ArgumentGroup {
        @Opt(
            "root",
            short: "r",
            help: "Working directory retained for command compatibility."
        )
        public var root: String?

        @Flag(
            "force",
            help: "Use SIGKILL immediately instead of attempting SIGTERM first."
        )
        public var force: Bool

        @Flag(
            "dry-run",
            help: "Only show the processes that would be terminated."
        )
        public var dryRun: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Inspect and kill running Swift/SwiftPM processes."
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
        let rootPath = (
            options.root ?? FileManager.default.currentDirectoryPath
        ) as NSString

        let expandedRootPath = rootPath.expandingTildeInPath
        let directory = URL(
            fileURLWithPath: expandedRootPath,
            isDirectory: true
        )

        print("KillSwiftPM".ansi(.bold))
        print("Root: \(expandedRootPath)".ansi(.brightBlack))
        print(
            "Force: "
                + (options.force ? "ON".ansi(.yellow) : "off".ansi(.brightBlack))
        )
        print(
            "Dry run: "
                + (options.dryRun ? "ON".ansi(.yellow) : "off".ansi(.brightBlack))
        )
        print()

        let processes = try await SwiftPMProcesses().killAll(
            force: options.force,
            dryRun: options.dryRun,
            cwd: directory
        )

        if options.dryRun, !processes.isEmpty {
            print()
            print(
                "Dry run enabled; no signals were sent.".ansi(.yellow)
            )
        }
    }
}
