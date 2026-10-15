import Arguments
import Foundation

public enum SwiftTestCommand: BoundArgumentCommand {
    public static let name = "test"

    public enum SelectionError: Error, LocalizedError {
        case conflictingOptions
        public var errorDescription: String? {
            "Choose only one of --all, --group and --product."
        }
    }

    public struct Options: ArgumentGroup {
        @Opt("project", short: "p", help: "Project directory (defaults to CWD).")
        public var project: String?

        @Flag("all", help: "Run all declared test products, without duplicates.")
        public var all: Bool

        @Opt("group", help: "Run a named test group.")
        public var group: String?

        @Opt("product", help: "Run one explicitly declared test product.")
        public var product: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("Run executable test products declared in local build-object.pkl tests { }."),
            try params(Options.self),
        ]
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let choices = [options.all, options.group != nil, options.product != nil].filter { $0 }.count
        guard choices <= 1 else { throw SelectionError.conflictingOptions }
        let selection: TestConfiguration.Selection
        if options.all { selection = .all }
        else if let group = options.group { selection = .group(group) }
        else if let product = options.product { selection = .product(product) }
        else { selection = .primary }

        let root = options.project.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let plan = try await Tests.resolve(at: root, selection: selection)
        print("Running \(plan.products.count) test product(s) in \(plan.project.path)")
        try await Tests.execute(plan)
    }
}
