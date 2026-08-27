import Arguments
import Foundation
import plate

public enum SwiftBuildCommand: BoundArgumentCommand {
    public static let name = "build"

    public struct Options: ArgumentGroup {
        @Flag(
            "debug",
            short: "d",
            help: "Build in debug mode."
        )
        public var debug: Bool

        @Flag(
            "local",
            short: "l",
            help: "Keep artifacts in .build (no deploy)."
        )
        public var local: Bool

        @Flag(
            "repo",
            short: "r",
            help: "Keep artifacts in .build (no deploy)."
        )
        public var repo: Bool

        @Flag(
            "no-move",
            help: "Keep artifacts in .build (no deploy)."
        )
        public var noMove: Bool

        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        @Opt(
            "destination",
            short: "o",
            help: "Destination path for deployed binary (defaults to ~/sbm-bin)."
        )
        public var destination: String?

        @Opts(
            "products",
            take: .many,
            help: "Deploy only these executable products (comma-separated or repeatable)."
        )
        public var products: [String]

        @Opts(
            "targets",
            take: .many,
            help: "Deprecated compatibility selector: select products by executable target name."
        )
        public var legacyTargets: [String]

        @Opts(
            "skip-products",
            take: .many,
            help: "Skip these executable products (comma-separated or repeatable)."
        )
        public var skipProducts: [String]

        @Opts(
            "skip-targets",
            take: .many,
            help: "Deprecated compatibility selector: skip products by executable target name."
        )
        public var legacySkipTargets: [String]

        @Flag(
            "cli-only",
            help: "Deploy products backed by CLI-like executable targets only."
        )
        public var cliOnly: Bool

        @Flag(
            "keep-apps",
            help: "Keep products backed by app-like targets in .build instead of deploying them."
        )
        public var keepApps: Bool

        @Opts(
            "map",
            take: .many,
            help: "Per-product destination mapping 'name=/path'. Legacy target names remain accepted."
        )
        public var map: [String]

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Build a Swift package (debug/release) and optionally deploy to '~/sbm-bin/'."
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
        let buildRequest: Build.Request

        if hasExplicitInput(invocation) {
            buildRequest = try request(
                from: options,
                source: .direct(
                    arguments: auditArguments(
                        from: options
                    )
                )
            )
        } else {
            buildRequest = try projectDefaultRequest(
                from: URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath,
                    isDirectory: true
                )
            )
        }

        let plan = try await Build.resolve(
            buildRequest
        )

        present(
            plan
        )

        _ = try await Build.execute(
            plan
        )
    }

    public static func projectDefaultRequest(
        from directory: URL,
        updateBuiltOnSuccess: Bool = true
    ) throws -> Build.Request {
        guard
            let objectURL = try? BuildObjectConfiguration
                .traverseForBuildObjectPkl(
                    from: directory
                ),
            let configuration = try? BuildObjectConfiguration(
                from: objectURL
            ),
            configuration.compile.use
        else {
            return Build.Request(
                project: directory,
                config: .init(
                    mode: .release,
                    updateBuiltOnSuccess: updateBuiltOnSuccess
                ),
                source: .direct(
                    arguments: []
                )
            )
        }

        var arguments = configuration.compile.arguments

        if let first = arguments.first?.lowercased(),
           first == "build" || first == "sbm" {
            arguments.removeFirst()
        }

        let parsed = try Arguments.parse(
            arguments,
            spec: try spec()
        )

        let options = try parsed.options(
            Options.self
        )

        let request = try request(
            from: options,
            source: .buildObject(
                url: objectURL,
                arguments: arguments
            ),
            defaultProject: directory,
            updateBuiltOnSuccess: updateBuiltOnSuccess
        )

        return request
    }

    public static func request(
        arguments: [String],
        defaultProject: URL,
        updateBuiltOnSuccess: Bool = true
    ) throws -> Build.Request {
        guard !arguments.isEmpty else {
            return try projectDefaultRequest(
                from: defaultProject,
                updateBuiltOnSuccess: updateBuiltOnSuccess
            )
        }

        let parsed = try Arguments.parse(
            arguments,
            spec: try spec()
        )

        let options = try parsed.options(
            Options.self
        )

        return try request(
            from: options,
            source: .direct(
                arguments: arguments
            ),
            defaultProject: defaultProject,
            updateBuiltOnSuccess: updateBuiltOnSuccess
        )
    }
}

extension SwiftBuildCommand {
    package static func present(
        _ plan: Build.Plan
    ) {
        for line in presentationLines(
            for: plan
        ) {
            print(line)
        }
    }

    package static func presentationLines(
        for plan: Build.Plan
    ) -> [String] {
        var lines: [String] = []

        switch plan.request.source {
        case .direct:
            break

        case .buildObject(_, let arguments):
            let quoted = arguments
                .map(String.init(reflecting:))
                .joined(separator: " ")

            let effective = arguments
                .joined(separator: " ")

            lines.append(
                "Detected preconfigured build instructions, intercepting build commands."
            )
            lines.append(
                "    (You provided no overriding flags or options)."
            )
            lines.append("")
            lines.append(
                "    Arguments found: \(quoted)"
            )
            lines.append(
                "    Invocation (effective): sbm \(effective)"
            )
            lines.append("")
        }

        let selection = plan.request.selection
        let usesDefaultProductSelection =
            selection.products.isEmpty
            && selection.legacyTargets.isEmpty
            && selection.skippedProducts.isEmpty
            && selection.legacySkippedTargets.isEmpty
            && !selection.cliOnly
            && !selection.keepApps

        let products: String

        if usesDefaultProductSelection {
            products = "all executable products"
        } else if plan.selectedProductNames.isEmpty {
            products = "none"
        } else {
            products = plan.selectedProductNames.joined(
                separator: ", "
            )
        }

        lines.append(
            "Building \(plan.request.project.lastPathComponent)"
        )
        lines.append(
            "    mode      \(plan.request.config.buildDirComponent)"
        )
        lines.append(
            "    products  \(products)"
        )
        lines.append(
            "    project   \(plan.request.project.path)"
        )
        lines.append(
            "    source    \(plan.request.source.description)"
        )
        lines.append("")

        return lines
    }
}

private extension SwiftBuildCommand {
    static func request(
        from options: Options,
        source: Build.Request.Source,
        defaultProject: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        updateBuiltOnSuccess: Bool = true
    ) throws -> Build.Request {
        let project = options.project.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? defaultProject

        let destination = options.destination.map {
            URL(
                fileURLWithPath: $0,
                isDirectory: true
            )
        } ?? Build.defaultDeploymentDirectory

        return Build.Request(
            project: project,
            config: .init(
                mode: options.debug ? .debug : .release,
                updateBuiltOnSuccess: updateBuiltOnSuccess
            ),
            destination: destination,
            deploy: !(options.local || options.repo || options.noMove),
            selection: .init(
                products: Set(
                    csvValues(options.products)
                ),
                legacyTargets: Set(
                    csvValues(options.legacyTargets)
                ),
                skippedProducts: Set(
                    csvValues(options.skipProducts)
                ),
                legacySkippedTargets: Set(
                    csvValues(options.legacySkipTargets)
                ),
                cliOnly: options.cliOnly,
                keepApps: options.keepApps,
                destinationMappings: destinationMap(
                    options.map
                )
            ),
            source: source
        )
    }

    static func hasExplicitInput(
        _ invocation: ParsedInvocation
    ) -> Bool {
        !invocation.values.isEmpty
            || !invocation.repeatedValues.isEmpty
            || !invocation.flags.isEmpty
            || !invocation.passthrough.isEmpty
    }

    static func csvValues(
        _ values: [String]
    ) -> [String] {
        values
            .flatMap {
                $0.split(
                    separator: ","
                )
            }
            .map {
                String($0).trimmingCharacters(
                    in: .whitespaces
                )
            }
            .filter {
                !$0.isEmpty
            }
    }

    static func destinationMap(
        _ values: [String]
    ) -> [String: URL] {
        var result: [String: URL] = [:]

        for value in values {
            let parts = value.split(
                separator: "=",
                maxSplits: 1
            )

            guard parts.count == 2 else {
                continue
            }

            result[String(parts[0])] = URL(
                fileURLWithPath: String(parts[1]),
                isDirectory: true
            )
        }

        return result
    }

    static func auditArguments(
        from options: Options
    ) -> [String] {
        var arguments: [String] = []

        if options.debug {
            arguments.append("--debug")
        }

        if options.local {
            arguments.append("--local")
        }

        if options.repo {
            arguments.append("--repo")
        }

        if options.noMove {
            arguments.append("--no-move")
        }

        if let project = options.project {
            arguments += ["--project", project]
        }

        if let destination = options.destination {
            arguments += ["--destination", destination]
        }

        func appendMany(
            _ name: String,
            _ values: [String]
        ) {
            for value in values {
                arguments += ["--\(name)", value]
            }
        }

        appendMany("products", options.products)
        appendMany("targets", options.legacyTargets)
        appendMany("skip-products", options.skipProducts)
        appendMany("skip-targets", options.legacySkipTargets)

        if options.cliOnly {
            arguments.append("--cli-only")
        }

        if options.keepApps {
            arguments.append("--keep-apps")
        }

        appendMany("map", options.map)

        return arguments
    }
}
