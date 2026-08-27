import Arguments
import Foundation
import Terminal
import plate

public enum SwiftRenewRepositoriesCommand: BoundArgumentCommand {
    public static let name = "renew-repositories"
    public static let aliases = [
        "renew",
        "rr",
    ]

    public struct Options: ArgumentGroup {
        @Opt(
            "root",
            short: "r",
            help: "Root directory to scan (defaults to current working directory)."
        )
        public var root: String?

        @Opt(
            "max-depth",
            default: 6,
            help: "Maximum directory depth to scan relative to root (0 = only root). Defaults to 6."
        )
        public var maxDepth: Int

        @Flag(
            "safe",
            help: "Safe mode: do not discard local commits / dirty worktrees."
        )
        public var safe: Bool

        @Flag(
            "dry-run",
            help: "Dry run: only list detected projects without updating them."
        )
        public var dryRun: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Traverse a workspace and run ObjectRenewer on all detected Git repos."
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
        let rootPath = options.root ?? FileManager.default.currentDirectoryPath
        let criteria = ObjectComparisonCriteria(
            upstream: false,
            compiled: true
        )

        print("RenewRepositories".ansi(.bold))
        print("Root: \(rootPath)".ansi(.brightBlack))
        print("Max depth: \(options.maxDepth)".ansi(.brightBlack))
        print(
            "Safe mode: "
                + (options.safe ? "ON".ansi(.yellow) : "off".ansi(.brightBlack))
        )
        print(
            "Dry run: "
                + (options.dryRun ? "ON".ansi(.yellow) : "off".ansi(.brightBlack))
        )
        print("Criteria: upstream=\(criteria.upstream), compiled=\(criteria.compiled)".ansi(.brightBlack))
        print()

        let objects = try ObjectRenewer.discover(
            rootPath: rootPath,
            maxDepth: options.maxDepth,
            criteria: criteria
        )

        if objects.isEmpty {
            print(
                "No build-object.pkl projects detected under root.".ansi(.yellow)
            )
            return
        }

        print("Discovered \(objects.count) projects:\n".ansi(.brightBlack))

        for object in objects {
            let description: String

            switch object.compilable {
            case .some(true):
                description = "compilable"

            case .some(false):
                description = "non-compilable"

            case .none:
                description = "compilable (default)"
            }

            print(
                "• ".ansi(.brightBlack)
                    + object.path.ansi(.bold)
                    + "  [\(description)]".ansi(.brightBlack)
            )
        }

        print()

        guard !options.dryRun else {
            print(
                "Dry run enabled; skipping ObjectRenewer.update().".ansi(.yellow)
            )
            return
        }

        print(
            "Running ObjectRenewer.update on discovered projects…".ansi(.brightBlack)
        )
        print()

        try await ObjectRenewer.update(
            objects: objects,
            safe: options.safe
        )
    }
}
