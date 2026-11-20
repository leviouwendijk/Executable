import Foundation
import Frame

/// The `Executable` Frame module: what `import Executable;` makes nameable in package.frame.
/// `install()` writes it where editors find it.
///
/// Beside a project's Package.swift:
///
///     import Executable;
///
///     let package: Package = .{
///         .build = .{ .arguments = ["--skip-products", "unifi_debug"] },
///         .deploy = .{ .products = ["unifi"] },
///     };
///
/// Beside a test package's Package.swift (`Tests/package.frame`):
///
///     import Executable;
///
///     let tests: Tests = .{
///         .primary = "t_unifi",
///         .groups = .{ .client = ["t_unifi_client"] },
///         .interactive = ["t_unifi_shell"],
///         .live = ["t_unifi_live"],
///     };
public enum ExecutableFrame {
    public static let module = Frame.Module("Executable", types: [
        .decodable(PackageFrame.PackageFields.self, named: "Package"),
        .decodable(PackageFrame.TestsFields.self, named: "Tests"),
        .decodable(PackageFrame.BenchmarksFields.self, named: "Benchmarks"),
        .decodable(SbmSettings.Fields.self, named: "Settings"),
        .decodable(KeepList.Fields.self, named: "Keep"),
    ])

    public static let environment = Frame.Environment([module])

    /// Writes `Executable.frame` where editors look for module files.
    @discardableResult
    public static func install(into directory: URL = Frame.modulesDirectory) throws -> URL {
        try module.install(into: directory)
    }
}

/// Reads and writes package.frame. Its binding's type says what the package is.
public enum PackageFrame {
    public static let fileName = "package.frame"

    public enum Description: Sendable, Equatable {
        case package(PackageConfiguration)
        case tests(TestConfiguration)
        case benchmarks(TestConfiguration)
    }

    public static func parse(_ source: String) throws -> Description {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        let declared = [
            ("package", "Package"), ("tests", "Tests"), ("benchmarks", "Benchmarks"),
        ].filter { name, type in document.binding(named: name)?.type?.components.last == type }
        guard declared.count <= 1 else { throw PackageFrameError.both_bindings }
        switch declared.first?.0 {
        case "package":
            return .package(try configuration(document.decode(PackageFields.self, binding: "package")))
        case "tests":
            return .tests(configuration(try document.decode(TestsFields.self, binding: "tests")))
        case "benchmarks":
            return .benchmarks(configuration(try document.decode(BenchmarksFields.self, binding: "benchmarks")))
        default:
            throw PackageFrameError.missing_binding
        }
    }

    public static func read(_ url: URL) throws -> Description {
        try BuildObjectFile.read(from: url, decoding: parse)
    }

    /// What `initialize(in:)` wrote; nil where a package.frame already existed or nothing applies.
    public struct Initialized: Sendable, Equatable {
        public let package: URL?
        public let tests: URL?
        public let benchmarks: URL?
    }

    /// Writes `let package: Package = .{};` beside the project's Package.swift, and
    /// `let tests: Tests = .{};` / `let benchmarks: Benchmarks = .{};` in `Tests/` and
    /// `Benchmarks/` when they hold a Package.swift. Existing files are kept; a legacy
    /// build-object.pkl is refused.
    public static func initialize(in project: URL) throws -> Initialized {
        let project = project.standardizedFileURL
        if let legacy = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: project),
           try BuildObjectDiscovery.local(named: fileName, in: project) == nil {
            throw ConfigurationFileError.legacy(legacy)
        }
        let package = try create(source(PackageConfiguration()), in: project)
        let layout = PackageLayout()
        func nested(_ part: PackageLayout.Nested, _ source: String) throws -> URL? {
            let directory = PackageLayout.url(part.root, in: project)
            guard try BuildObjectDiscovery.local(named: "Package.swift", in: directory) != nil else { return nil }
            return try create(source, in: directory)
        }
        return .init(
            package: package,
            tests: try nested(layout.tests, source(TestConfiguration())),
            benchmarks: try nested(layout.benchmarks, source(benchmarks: TestConfiguration()))
        )
    }

    private static func create(_ source: String, in directory: URL) throws -> URL? {
        guard try BuildObjectDiscovery.local(named: fileName, in: directory) == nil else { return nil }
        let file = directory.appendingPathComponent(fileName)
        try BuildObjectDiscovery.requireOwned(file, by: directory)
        try BuildObjectFile.write(source, to: file)
        return file
    }

    /// The `.wipe` policy of the package.frame in `directory`, whatever its kind; nil without one.
    public static func wipe(in directory: URL) throws -> WipePolicy? {
        guard let file = try BuildObjectDiscovery.local(named: fileName, in: directory) else { return nil }
        switch try read(file) {
        case .package(let package): return package.wipe
        case .tests(let tests), .benchmarks(let tests): return tests.wipe
        }
    }

    /// The `package` binding beside a Package.swift, or nil when the directory has no package.frame.
    public static func package(in directory: URL) throws -> PackageConfiguration? {
        guard let file = try BuildObjectDiscovery.local(named: fileName, in: directory) else { return nil }
        guard case .package(let package) = try read(file) else { throw PackageFrameError.not_a_package(file) }
        return package
    }

    public static func source(_ package: PackageConfiguration) throws -> String {
        try source("package", ofType: "Package", PackageFields(
            build: package.buildArguments.isEmpty ? nil : .init(arguments: package.buildArguments),
            deploy: package.deployProducts.map { .init(products: $0) },
            mode: package.mode,
            wipe: package.wipe.map { .init(above: $0.above) }
        ))
    }

    public static func source(_ tests: TestConfiguration) throws -> String {
        try source("tests", ofType: "Tests", TestsFields(
            primary: tests.primary,
            groups: tests.groups.isEmpty ? nil : tests.groups,
            interactive: tests.interactive.isEmpty ? nil : tests.interactive,
            live: tests.live.isEmpty ? nil : tests.live,
            mode: tests.mode,
            wipe: tests.wipe.map { .init(above: $0.above) }
        ))
    }

    public static func source(benchmarks: TestConfiguration) throws -> String {
        try source("benchmarks", ofType: "Benchmarks", BenchmarksFields(
            primary: benchmarks.primary,
            groups: benchmarks.groups.isEmpty ? nil : benchmarks.groups,
            interactive: benchmarks.interactive.isEmpty ? nil : benchmarks.interactive,
            mode: benchmarks.mode,
            wipe: benchmarks.wipe.map { .init(above: $0.above) }
        ))
    }

    private static func source<T: Encodable>(_ name: String, ofType type: String, _ value: T) throws -> String {
        try Frame.document(
            imports: [ExecutableFrame.module.name],
            bindings: [(name: name, type: type, value: value)]
        ).source
    }

    private static func configuration(_ fields: PackageFields) throws -> PackageConfiguration {
        if let deploy = fields.deploy, deploy.products.isEmpty {
            throw PackageFrameError.empty_deploy
        }
        return .init(buildArguments: fields.build?.arguments ?? [], deployProducts: fields.deploy?.products, mode: fields.mode,
                     wipe: fields.wipe.map { .init(above: $0.above) })
    }

    private static func configuration(_ fields: TestsFields) -> TestConfiguration {
        .init(primary: fields.primary, groups: fields.groups ?? [:], interactive: fields.interactive ?? [], live: fields.live ?? [], mode: fields.mode,
              wipe: fields.wipe.map { .init(above: $0.above) })
    }

    private static func configuration(_ fields: BenchmarksFields) -> TestConfiguration {
        .init(primary: fields.primary, groups: fields.groups ?? [:], interactive: fields.interactive ?? [], mode: fields.mode,
              wipe: fields.wipe.map { .init(above: $0.above) })
    }
}

/// The written form; the native types stay free of Frame.
extension PackageFrame {
    struct PackageFields: Codable, Sendable, FrameDescribable {
        let build: BuildFields?
        let deploy: DeployFields?
        let mode: BuildMode?
        let wipe: WipeFields?

        static var frameSchema: Frame.Schema {
            .object([
                .init("build", .of(BuildFields.self)),
                .init("deploy", .of(DeployFields.self)),
                .init("mode", .of(BuildMode.self), summary: "How a flagless `sbm build` builds: .release (default) or .debug."),
                .init("wipe", .of(WipeFields.self)),
            ], summary: "How sbm builds and deploys the package beside this file: the `package` binding of package.frame.")
        }
    }

    struct BuildFields: Codable, Sendable, FrameDescribable {
        let arguments: [String]

        static var frameSchema: Frame.Schema {
            .object([
                .init("arguments", .array(.string), required: true, summary: "sbm build flags a flagless `sbm build` uses."),
            ], summary: "How a flagless `sbm build` builds.")
        }
    }

    struct DeployFields: Codable, Sendable, FrameDescribable {
        let products: [String]

        static var frameSchema: Frame.Schema {
            .object([
                .init("products", .array(.string), required: true,
                      summary: "Executable products a flagless `sbm build` builds and deploys to ~/sbm-bin; at least one."),
            ], summary: "What a flagless `sbm build` deploys; without it, nothing is deployed.")
        }
    }

    struct TestsFields: Codable, Sendable, FrameDescribable {
        let primary: String?
        let groups: [String: [String]]?
        let interactive: [String]?
        let live: [String]?
        let mode: BuildMode?
        let wipe: WipeFields?

        static var frameSchema: Frame.Schema {
            .object([
                .init("primary", .string, summary: "The product `sbm test` runs by default; optional when the package has one product."),
                .init("groups", .init(.any, summary: "Named lists of test products: .{ .flows = [\"t_name_flows\"] }.")),
                .init("interactive", .array(.string), summary: "Products that wait for input; `sbm test --all` skips them."),
                .init("live", .array(.string), summary: "Products that reach real services (network, credentials); `sbm test --live` runs them, `--all` skips them."),
                .init("mode", .of(BuildMode.self), summary: "How the products build and run: .debug (default) or .release."),
                .init("wipe", .of(WipeFields.self)),
            ], summary: "The test products of the test package beside this file: the `tests` binding of package.frame.")
        }
    }

    struct BenchmarksFields: Codable, Sendable, FrameDescribable {
        let primary: String?
        let groups: [String: [String]]?
        let interactive: [String]?
        let mode: BuildMode?
        let wipe: WipeFields?

        static var frameSchema: Frame.Schema {
            .object([
                .init("primary", .string, summary: "The product `sbm bench` runs by default; optional when the package has one product."),
                .init("groups", .init(.any, summary: "Named lists of benchmark products: .{ .hazard = [\"b_name_hazard\"] }.")),
                .init("interactive", .array(.string), summary: "Products that wait for input; `sbm bench --all` skips them."),
                .init("mode", .of(BuildMode.self), summary: "How the products build and run: .release (default) or .debug."),
                .init("wipe", .of(WipeFields.self)),
            ], summary: "The benchmark products of the benchmark package beside this file, built in release: the `benchmarks` binding of package.frame.")
        }
    }
}

extension PackageFrame {
    struct WipeFields: Codable, Sendable, FrameDescribable {
        let above: ByteCount

        static var frameSchema: Frame.Schema {
            .object([
                .init("above", .init(.any, summary: "A size: .megabytes(500), .gigabytes(2.5) (also .kilobytes, .terabytes); after a successful run here, wipe .build and .index-build when together they exceed it."), required: true),
            ], summary: "Wipe this package's caches after a successful build, test or bench run when they grow past a size (the keep list applies).")
        }
    }
}

public enum PackageFrameError: Error, Sendable, LocalizedError {
    case missing_binding
    case both_bindings
    case empty_deploy
    case not_a_package(URL)
    case not_tests(URL)

    public var errorDescription: String? {
        switch self {
        case .missing_binding: return "package.frame must declare `let package: Package`, `let tests: Tests` or `let benchmarks: Benchmarks`."
        case .both_bindings: return "package.frame declares more than one of `package`, `tests` and `benchmarks`; a package is one of them."
        case .empty_deploy: return "package.frame .deploy.products must name at least one product."
        case .not_a_package(let url): return "\(url.path) describes a test package, not a package to build."
        case .not_tests(let url): return "\(url.path) describes a package to build, not a test package."
        }
    }
}
