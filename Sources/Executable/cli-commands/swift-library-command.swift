import Arguments
import Foundation

public enum SwiftLibraryCommand: BoundArgumentCommand {
    public static let name = "lib"

    public struct Options: ArgumentGroup {
        @Flag(
            "release",
            short: "r",
            help: "Build in release mode."
        )
        public var release: Bool

        @Flag(
            "debug",
            short: "d",
            help: "Build in debug mode."
        )
        public var debug: Bool

        @Flag(
            "local",
            short: "l",
            help: "Keep artifacts local (.build) — no export."
        )
        public var local: Bool

        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        @Opt(
            "modules-root",
            short: "m",
            help: "Modules root (defaults to ~/sbm-bin/modules)."
        )
        public var modulesRoot: String?

        public init() {}
    }

    public enum CommandError:
        Error,
        Sendable,
        LocalizedError,
        Equatable
    {
        case conflictingModes

        public var errorDescription: String? {
            "Choose exactly one of --release or --debug."
        }
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Build library with module interfaces and export artifacts."
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
        guard !(options.release && options.debug) else {
            throw CommandError.conflictingModes
        }

        let directory = options.project.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        let modulesRoot = options.modulesRoot.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? BuildLibrary.defaultModulesRoot

        _ = try await BuildLibrary.buildAndExport(
            at: directory,
            config: .init(
                mode: options.debug ? .debug : .release
            ),
            local: options.local,
            modulesRoot: modulesRoot
        )
    }
}
