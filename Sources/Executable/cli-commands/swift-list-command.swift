import Arguments
import Foundation
import Terminal

public enum SwiftListCommand: BoundArgumentCommand {
    public static let name = "list"

    public struct Options: ArgumentGroup {
        @Flag(
            "detail",
            short: "d",
            help: "Show details."
        )
        public var detail: Bool

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
                "List binaries in sbm-bin."
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

        let items = try DeployedList.listBinaries(
            at: destination,
            includeDetails: options.detail
        )

        if items.isEmpty {
            print(
                "No binaries in \(destination.path)".ansi(.yellow)
            )
            return
        }

        if !options.detail {
            for item in items {
                print(
                    "• \(item.name)".ansi(.bold)
                )
            }
            return
        }

        for item in items {
            print("\n\(item.name)".ansi(.bold))
            print("  path: \(item.path.path)".ansi(.brightBlack))

            if let metadata = item.metadata {
                print("  project: \(metadata.projectRootPath)".ansi(.brightBlack))
                print("  build:   \(metadata.buildType)".ansi(.brightBlack))
                print("  when:    \(metadata.deployedAt)".ansi(.brightBlack))
                print("  dest:    \(metadata.destinationRoot)".ansi(.brightBlack))
            } else {
                print("  (no metadata)".ansi(.brightBlack))
            }
        }

        print("")
    }
}
