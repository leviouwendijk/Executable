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

        @Flag("all", help: "Run every product except the interactive ones.")
        public var all: Bool

        @Opt("group", help: "Run a named group.")
        public var group: String?

        @Opt("product", help: "Run one product.")
        public var product: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("Run the test products of the nested Tests/ package, as declared in its package.frame (debug)."),
            try params(Options.self),
        ]
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        try await run(options, kind: .tests)
    }

    static func run(_ options: Options, kind: Tests.Kind) async throws {
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
        try await run(at: root, selection: selection, kind: kind)
    }

    static func run(at root: URL, selection: TestConfiguration.Selection, kind: Tests.Kind) async throws {
        let plan = try await Tests.resolve(at: root, selection: selection, kind: kind)
        for run in plan.runs {
            print("\(run.package.appendingPathComponent("Package.swift").path): \(run.products.joined(separator: ", "))")
        }
        try await Tests.execute(plan)
    }
}

public enum SwiftBenchCommand: BoundArgumentCommand {
    public static let name = "bench"

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about("Run the benchmark products of the nested Benchmarks/ package, as declared in its package.frame (release)."),
            try params(SwiftTestCommand.Options.self),
        ]
    }

    public static func run(
        _ options: SwiftTestCommand.Options,
        invocation: ParsedInvocation
    ) async throws {
        try await SwiftTestCommand.run(options, kind: .benchmarks)
    }
}
