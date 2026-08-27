import Arguments
import Foundation
import Terminal

public enum SwiftSetupCommand: BoundArgumentCommand {
    public static let name = "setup"

    public struct Options: ArgumentGroup {
        @Opt(
            "destination",
            short: "o",
            help: "Destination root (defaults to ~/sbm-bin)."
        )
        public var destination: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Setup the sbm-bin directory"
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
        let destination = options.destination.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? Build.defaultDeploymentDirectory

        let created = try DeploymentDirectory.ensureExists(
            at: destination
        )

        if created {
            print(
                "Created '\(destination.path)'.".ansi(.green)
            )
        } else {
            print(
                "'\(destination.path)' already exists, so "
                    + "sbm*".ansi(.bold)
                    + " is properly set up."
            )
        }
    }
}
