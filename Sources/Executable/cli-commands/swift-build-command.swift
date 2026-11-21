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
            "release",
            help: "Build in release mode, whatever package.frame's .mode says."
        )
        public var release: Bool

        @Flag(
            "local",
            short: "l",
            help: "Keep artifacts in .build: no deploy, even when package.frame's .deploy says to."
        )
        public var local: Bool

        @Flag(
            "deploy",
            help: "Deploy the selected products, even when package.frame has no .deploy (or with --ignore-frame)."
        )
        public var deploy: Bool

        @Flag(
            "ignore-frame",
            help: "Build from these flags alone: package.frame is not read, so nothing is signed or deployed unless a flag says so."
        )
        public var ignoreFrame: Bool

        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        @Flag(
            "inherit-ancestor",
            help: "Opt in to a parent package.frame or build-object.pkl. Requires interactive 'yes' confirmation."
        )
        public var inheritAncestor: Bool

        @Opt(
            "destination",
            short: "o",
            help: "Destination path for deployed binary (defaults to ~/sbm-bin)."
        )
        public var destination: String?

        @Opts(
            "products",
            take: .many,
            help: "Build only these executable products (comma-separated or repeatable); replaces package.frame's selection. They deploy when --deploy is given, or when package.frame's .deploy lists them all."
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

        @Opt(
            "sign",
            help: "Code-sign selected executable products using ad-hoc, apple-development, developer-id-application, apple-distribution, or fingerprint:<SHA1>."
        )
        public var signingIdentity: String?

        @Opt(
            "sign-identifier",
            help: "Explicit code-signing identifier applied to selected products."
        )
        public var signingIdentifier: String?

        @Opt(
            "sign-entitlements",
            help: "Entitlements plist used while code-signing. Relative paths resolve from the project root."
        )
        public var signingEntitlements: String?

        @Flag(
            "sign-hardened-runtime",
            help: "Enable the hardened runtime while code-signing."
        )
        public var signingHardenedRuntime: Bool

        @Flag(
            "test",
            short: "t",
            help: "Run the Tests/ package's primary products first; a failure stops the build and deploy."
        )
        public var test: Bool

        @Flag(
            "bench",
            alias: "benchmark",
            help: "Run the Benchmarks/ package's primary products after the build (release)."
        )
        public var bench: Bool

        @Flag(
            "build",
            short: "b",
            help: "Build (what this command does anyway); here so `-b` means the same as on `sbm pack`."
        )
        public var build: Bool

        @Group("tidy")
        public var tidy: SwiftTidyOptions

        public init() {}

        var steps: SwiftBuildSteps {
            SwiftBuildSteps(test: test, bench: bench).with(tidy)
        }
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Build a Swift package. Flags override package.frame field by field (mode, products, signing, deploy); --ignore-frame builds from the flags alone. Nothing deploys unless package.frame's .deploy or --deploy says so."
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

        if options.inheritAncestor {
            // The opt-in means "use discovered defaults", not "override with direct flags".
            let provided = auditArguments(from: options)
            var permitted: [String] = []
            if let project = options.project { permitted += ["--project", project] }
            permitted.append("--inherit-ancestor")
            guard provided == permitted else {
                throw BuildObjectDiscoveryError.inheritanceOptionsConflict
            }

            let directory = options.project.map {
                URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
            } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let local = try BuildObjectDiscovery.configuration(in: directory)
            var approvedAncestor: URL?
            if local == nil,
               let candidate = try? BuildObjectDiscovery.nearestConfiguration(from: directory, maxDepth: 5) {
                print("Project: \(directory.path)")
                print("Ancestor configuration: \(candidate.path)")
                print("Apply its build arguments to this project? Type 'yes' to confirm:")
                guard readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "yes" else {
                    throw BuildObjectDiscoveryError.ancestorConfirmationDeclined(candidate)
                }
                approvedAncestor = candidate
            }
            buildRequest = try projectDefaultRequest(
                from: directory,
                approvedAncestorConfiguration: approvedAncestor
            )
        } else if options.ignoreFrame {
            buildRequest = try request(
                from: options,
                frame: nil,
                source: .direct(arguments: auditArguments(from: options))
            )
        } else {
            let directory = options.project.map {
                URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
            } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            buildRequest = try projectDefaultRequest(
                from: directory,
                overrides: hasExplicitInput(invocation) ? options : nil
            )
        }

        try await options.steps.before(
            at: buildRequest.project
        )

        let plan = try await Build.resolve(
            buildRequest
        )

        present(
            plan
        )

        _ = try await Build.execute(
            plan
        )

        try await options.steps.after(
            at: buildRequest.project
        )
    }

    /// The request for a build in `directory`: its package.frame, with `overrides` (the flags
    /// of this run) replacing it field by field. Without a package.frame, the flags alone.
    public static func projectDefaultRequest(
        from directory: URL,
        approvedAncestorConfiguration: URL? = nil,
        overrides: Options? = nil
    ) throws -> Build.Request {
        let root = directory.standardizedFileURL
        let flags = try overrides ?? emptyOptions()
        let flagSource: Build.Request.Source = .direct(arguments: overrides.map(auditArguments(from:)) ?? [])
        let local = try BuildObjectDiscovery.configuration(in: root)
        let objectURL: URL?
        if let local {
            objectURL = local
        } else if let approvedAncestorConfiguration {
            let candidate = try BuildObjectDiscovery.nearestConfiguration(from: root, maxDepth: 5)
            guard candidate.standardizedFileURL == approvedAncestorConfiguration.standardizedFileURL else {
                throw BuildObjectDiscoveryError.ancestorNotApproved(approvedAncestorConfiguration)
            }
            objectURL = candidate
        } else {
            objectURL = nil
        }

        // Malformed local configuration is an error, not an invitation to search upwards.
        guard let objectURL, let package = try packageConfiguration(from: objectURL) else {
            return try request(from: flags, frame: nil, source: flagSource, defaultProject: root)
        }

        var arguments = package.buildArguments
        if let first = arguments.first?.lowercased(), first == "build" || first == "sbm" {
            arguments.removeFirst()
        }
        let frameOptions = try Arguments.parse(arguments, spec: try spec()).options(Options.self)
        if let override = frameOptions.project {
            throw BuildObjectDiscoveryError.configurationOverridesProject(override)
        }
        if frameOptions.inheritAncestor || frameOptions.ignoreFrame {
            throw BuildObjectDiscoveryError.inheritanceOptionsConflict
        }

        let frameArguments = package.flaglessArguments ?? []
        let source: Build.Request.Source = overrides == nil
            ? .buildObject(url: objectURL, arguments: frameArguments)
            : .merged(url: objectURL, frame: frameArguments, flags: flagSource.arguments)
        return try request(
            from: flags,
            frame: .init(package: package, options: frameOptions),
            source: source,
            defaultProject: root
        )
    }

    /// The `package` binding of a package.frame; nil for a test or benchmark package, which
    /// builds plainly.
    static func packageConfiguration(from configuration: URL) throws -> PackageConfiguration? {
        guard configuration.lastPathComponent == PackageFrame.fileName else {
            throw ConfigurationFileError.legacy(configuration)
        }
        guard case .package(let package) = try PackageFrame.read(configuration) else { return nil }
        return package
    }

    public static func request(
        arguments: [String],
        defaultProject: URL
    ) throws -> Build.Request {
        guard !arguments.isEmpty else {
            return try projectDefaultRequest(
                from: defaultProject
            )
        }

        let parsed = try Arguments.parse(
            arguments,
            spec: try spec()
        )

        let options = try parsed.options(
            Options.self
        )

        if options.ignoreFrame {
            return try request(
                from: options,
                frame: nil,
                source: .direct(arguments: arguments),
                defaultProject: defaultProject
            )
        }

        return try projectDefaultRequest(
            from: options.project.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultProject,
            overrides: options
        )
    }

    static func emptyOptions() throws -> Options {
        try Arguments.parse([], spec: try spec()).options(Options.self)
    }
}

extension SwiftBuildCommand {
    /// Whether the invocation overrides any package.frame field. `-t`/`-b` and the tidy flags only
    /// add steps around the build, so `sbm -t` builds exactly the way package.frame says.
    @_spi(Testing) public static func hasExplicitInput(
        _ invocation: ParsedInvocation
    ) -> Bool {
        !invocation.values.isEmpty
            || !invocation.repeatedValues.isEmpty
            || invocation.flags.keys.contains { !SwiftBuildSteps.flagNames.contains($0) }
            || !invocation.passthrough.isEmpty
    }

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
            lines.append(
                "Building as package.frame says\(arguments.isEmpty ? "" : ": " + arguments.joined(separator: " "))."
            )
            lines.append("")

        case .merged(_, let frame, let flags):
            lines.append(
                "package.frame\(frame.isEmpty ? "" : " (" + frame.joined(separator: " ") + ")"), overridden by: \(flags.joined(separator: " "))"
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
            "    deploy    \(plan.request.deploy ? plan.request.destination.path : "no (stays in .build)")"
        )
        if let signing = plan.request.signing.defaultConfiguration {
            var line = "    signing   \(signing.identity.argumentValue)"
            if signing.missing != .fail {
                line += " (when missing: \(signing.missing == .adHoc ? "ad-hoc" : "unsigned"))"
            }
            lines.append(line)
        }
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

extension SwiftBuildCommand {
    /// What package.frame contributes to a build: its typed fields and its raw `.build.arguments`.
    struct FrameLayer {
        let package: PackageConfiguration
        let options: Options
    }
}

private extension SwiftBuildCommand {
    /// The request for `flags` over `frame`: each field comes from the flags when they set it,
    /// otherwise from package.frame (typed field first, then its raw arguments), otherwise the default.
    static func request(
        from flags: Options,
        frame: FrameLayer?,
        source: Build.Request.Source,
        defaultProject: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) throws -> Build.Request {
        let raw = frame?.options
        let package = frame?.package

        func many(_ flag: [String], _ frame: [String]?) -> [String] {
            flag.isEmpty ? csvValues(frame ?? []) : csvValues(flag)
        }

        let project = flags.project.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? defaultProject

        let destination = (flags.destination ?? raw?.destination).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? Build.defaultDeploymentDirectory

        guard !(flags.debug && flags.release) else {
            throw BuildFlagError.conflictingModes
        }
        let debug = flags.debug
            || (!flags.release && (package?.mode == .debug || raw?.debug == true))

        let products = flags.products.isEmpty
            ? (package?.deployProducts ?? csvValues(raw?.products ?? []))
            : csvValues(flags.products)

        guard !(flags.deploy && flags.local) else {
            throw BuildFlagError.conflictingDeploy
        }
        let deploy: Bool
        if flags.deploy {
            deploy = true
        } else if flags.local {
            deploy = false
        } else if let deployProducts = package?.deployProducts {
            // A flag's product selection deploys only what package.frame would deploy anyway.
            deploy = Set(products).isSubset(of: deployProducts)
        } else {
            deploy = raw?.deploy == true
        }

        let signing: Build.Signing
        if flags.signingIdentity != nil || flags.hasSigningModifiers {
            signing = try commandLineSigning(flags, project: project)
        } else if let raw, raw.signingIdentity != nil || raw.hasSigningModifiers {
            signing = try commandLineSigning(raw, project: project)
        } else if let packageSigning = package?.signing {
            signing = .init(
                defaultConfiguration: packageSigning.configuration(
                    in: project,
                    machineIdentity: SbmSettings.resolved.signIdentity
                )
            )
        } else {
            signing = .init()
        }

        return Build.Request(
            project: project,
            config: .init(
                mode: debug ? .debug : .release
            ),
            destination: destination,
            deploy: deploy,
            selection: .init(
                products: Set(products),
                legacyTargets: Set(many(flags.legacyTargets, raw?.legacyTargets)),
                skippedProducts: Set(many(flags.skipProducts, raw?.skipProducts)),
                legacySkippedTargets: Set(many(flags.legacySkipTargets, raw?.legacySkipTargets)),
                cliOnly: flags.cliOnly || raw?.cliOnly == true,
                keepApps: flags.keepApps || raw?.keepApps == true,
                destinationMappings: destinationMap(
                    flags.map.isEmpty ? (raw?.map ?? []) : flags.map
                )
            ),
            signing: signing,
            source: source
        )
    }

    /// Signing from `--sign` and its modifiers; the modifiers need `--sign`.
    static func commandLineSigning(
        _ options: Options,
        project: URL
    ) throws -> Build.Signing {
        guard let signingIdentity = options.signingIdentity else {
            throw CodeSigningConfigurationError.signingOptionsRequireIdentity
        }
        let selector = try CodeSigning.IdentitySelector(
            argument: signingIdentity
        )
        let entitlements = options.signingEntitlements.map { path in
            URL(
                fileURLWithPath: path,
                relativeTo: project
            )
            .standardizedFileURL
        }
        return .init(
            defaultConfiguration: .init(
                identity: selector,
                identifier: options.signingIdentifier,
                entitlements: entitlements,
                hardenedRuntime: options.signingHardenedRuntime
            )
        )
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

        if options.release {
            arguments.append("--release")
        }

        if options.local {
            arguments.append("--local")
        }

        if options.deploy {
            arguments.append("--deploy")
        }

        if options.ignoreFrame {
            arguments.append("--ignore-frame")
        }

        if let project = options.project {
            arguments += ["--project", project]
        }

        if options.inheritAncestor {
            arguments.append("--inherit-ancestor")
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

        if let signingIdentity = options.signingIdentity {
            arguments += [
                "--sign",
                signingIdentity,
            ]
        }

        if let signingIdentifier = options.signingIdentifier {
            arguments += [
                "--sign-identifier",
                signingIdentifier,
            ]
        }

        if let signingEntitlements = options.signingEntitlements {
            arguments += [
                "--sign-entitlements",
                signingEntitlements,
            ]
        }

        if options.signingHardenedRuntime {
            arguments.append(
                "--sign-hardened-runtime"
            )
        }

        return arguments
    }
}

extension SwiftBuildCommand.Options {
    var hasSigningModifiers: Bool {
        signingIdentifier != nil || signingEntitlements != nil || signingHardenedRuntime
    }
}

public enum BuildFlagError: Error, Sendable, LocalizedError, Equatable {
    case conflictingModes
    case conflictingDeploy

    public var errorDescription: String? {
        switch self {
        case .conflictingModes: "--debug and --release contradict each other."
        case .conflictingDeploy: "--deploy and --local contradict each other."
        }
    }
}
