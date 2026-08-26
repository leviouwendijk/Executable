import Arguments
import Foundation

public enum SwiftCleanCommand: BoundArgumentCommand {
    public static let name = "clean"

    public struct Options: ArgumentGroup {
        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "swift package clean"
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
        let directory = options.project.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        try await Build.clean(
            at: directory
        )
    }
}
