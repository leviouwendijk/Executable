import Primitives
import Arguments
import Foundation
import IO

public enum SwiftTestCommand: BoundArgumentCommand {
    public static let name = "test"

    public enum SelectionError: Error, LocalizedError {
        case conflictingOptions
        public var errorDescription: String? {
            "Choose only one of --all, --live, --group and --product."
        }
    }

    public struct Options: ArgumentGroup {
        @Opt("project", short: "p", help: "Project directory (defaults to CWD).")
        public var project: String?

        @Flag("all", help: "Run every product except the interactive and live ones.")
        public var all: Bool

        @Flag("live", help: "Run the live products (real services, network, credentials).")
        public var live: Bool

        @Opt("group", help: "Run a named group.")
        public var group: String?

        @Opt("product", help: "Run one product.")
        public var product: String?

        @Group("tidy")
        public var tidy: SwiftTidyOptions

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
        let choices = [options.all, options.live, options.group != nil, options.product != nil].filter { $0 }.count
        guard choices <= 1 else { throw SelectionError.conflictingOptions }
        let selection: TestConfiguration.Selection
        if options.all { selection = .all }
        else if options.live { selection = .live }
        else if let group = options.group { selection = .group(group) }
        else if let product = options.product { selection = .product(product) }
        else { selection = .primary }

        let root = try options.project.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileSystem.cwd()
        try await run(at: root, selection: selection, kind: kind, steps: SwiftBuildSteps().with(options.tidy))
    }

    /// Runs the plan. With `steps` (the `test`/`bench` commands themselves), tidies the packages
    /// it ran in before and after, including their `.wipe.above`; build and pack pass none,
    /// because their own after-step covers these packages.
    static func run(
        at root: URL,
        selection: TestConfiguration.Selection,
        kind: Tests.Kind,
        steps: SwiftBuildSteps? = nil,
        output: TextSink = .standard
    ) async throws {
        let plan = try await Tests.resolve(at: root, selection: selection, kind: kind)
        var packages: [URL] = []
        for run in plan.runs where !packages.contains(run.package) {
            packages.append(run.package)
        }
        if let steps {
            try await SwiftBuildSteps.tidy(packages, clean: steps.cleanBefore, wipe: steps.wipeBefore, output: output)
        }
        for run in plan.runs {
            output.line("\(run.package.appendingPathComponent("Package.swift").path): \(run.products.joined(separator: ", "))")
        }
        try await Tests.execute(plan, output: output)
        if let steps {
            try await SwiftBuildSteps.tidyAfter(packages, clean: steps.clean, wipe: steps.wipe, output: output)
        }
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
