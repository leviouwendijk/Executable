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
///         .groups = .{ .live = ["t_unifi_live"] },
///         .interactive = ["t_unifi_shell"],
///     };
public enum ExecutableFrame {
    public static let module = Frame.Module("Executable", types: [
        .decodable(PackageFrame.PackageFields.self, named: "Package"),
        .decodable(PackageFrame.TestsFields.self, named: "Tests"),
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
    }

    public static func parse(_ source: String) throws -> Description {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        let package = document.binding(named: "package")?.type?.components.last == "Package"
        let tests = document.binding(named: "tests")?.type?.components.last == "Tests"
        switch (package, tests) {
        case (true, true):
            throw PackageFrameError.both_bindings
        case (true, false):
            return .package(try configuration(document.decode(PackageFields.self, binding: "package")))
        case (false, true):
            return .tests(configuration(try document.decode(TestsFields.self, binding: "tests")))
        case (false, false):
            throw PackageFrameError.missing_binding
        }
    }

    public static func read(_ url: URL) throws -> Description {
        try BuildObjectFile.read(from: url, decoding: parse)
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
            deploy: package.deployProducts.map { .init(products: $0) }
        ))
    }

    public static func source(_ tests: TestConfiguration) throws -> String {
        try source("tests", ofType: "Tests", TestsFields(
            primary: tests.primary,
            groups: tests.groups.isEmpty ? nil : tests.groups,
            interactive: tests.interactive.isEmpty ? nil : tests.interactive
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
        return .init(buildArguments: fields.build?.arguments ?? [], deployProducts: fields.deploy?.products)
    }

    private static func configuration(_ fields: TestsFields) -> TestConfiguration {
        .init(primary: fields.primary, groups: fields.groups ?? [:], interactive: fields.interactive ?? [])
    }
}

/// The written form; the native types stay free of Frame.
extension PackageFrame {
    struct PackageFields: Codable, Sendable, FrameDescribable {
        let build: BuildFields?
        let deploy: DeployFields?

        static var frameSchema: Frame.Schema {
            .object([
                .init("build", .of(BuildFields.self)),
                .init("deploy", .of(DeployFields.self)),
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

        static var frameSchema: Frame.Schema {
            .object([
                .init("primary", .string, summary: "The product `sbm test` runs by default; optional when the package has one product."),
                .init("groups", .init(.any, summary: "Named lists of test products: .{ .live = [\"t_name_live\"] }.")),
                .init("interactive", .array(.string), summary: "Products that wait for input; `sbm test --all` skips them."),
            ], summary: "The test products of the test package beside this file: the `tests` binding of package.frame.")
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
        case .missing_binding: return "package.frame must declare `let package: Package` or `let tests: Tests`."
        case .both_bindings: return "package.frame declares both `package` and `tests`; a package is one or the other."
        case .empty_deploy: return "package.frame .deploy.products must name at least one product."
        case .not_a_package(let url): return "\(url.path) describes a test package, not a package to build."
        case .not_tests(let url): return "\(url.path) describes a package to build, not a test package."
        }
    }
}
