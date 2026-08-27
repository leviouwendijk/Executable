import Arguments
import Foundation

public enum SwiftRemoveCommand: BoundArgumentCommand {
    public static let name = "remove"

    public struct Options: ArgumentGroup {
        @Opt(
            "destination",
            short: "o",
            help: "Destination root (defaults to ~/sbm-bin)."
        )
        public var destination: String?

        @Opts(
            "target",
            short: "t",
            take: .many,
            help: "Target(s) to remove (repeatable)."
        )
        public var targets: [String]

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Remove deployed binary and its metadata."
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

        for target in options.targets {
            try Remove.deployedBinary(
                named: target,
                at: destination
            )
        }
    }
}
