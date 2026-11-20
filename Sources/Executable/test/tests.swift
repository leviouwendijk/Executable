import Foundation
import IO

/// Resolves and runs executable test and benchmark products without a separate SwiftPM runner.
///
/// Both are nested packages directly below a project: a directory with a Package.swift
/// (depending on the project by path) and a package.frame declaring `let tests: Tests` or
/// `let benchmarks: Benchmarks`. `Tests/` and `Benchmarks/` are the conventional ones (see
/// `PackageLayout`); other directories declaring the same kind are found too. Tests run in
/// debug, benchmarks in release. Until a project's tests move, `Tests/package.frame` alone
/// (no Package.swift beside it) declares test products that still live in the project itself.
public enum Tests {
    public enum Kind: Sendable, Equatable {
        case tests
        case benchmarks

        /// The conventional directory, from `PackageLayout`.
        public var conventional: PackageLayout.Nested {
            switch self {
            case .tests: return PackageLayout().tests
            case .benchmarks: return PackageLayout().benchmarks
            }
        }

        public var mode: Build.Config.Mode {
            self == .tests ? .debug : .release
        }

        var noun: String { self == .tests ? "test" : "benchmark" }
        var declaration: String { self == .tests ? "let tests: Tests" : "let benchmarks: Benchmarks" }

        func configuration(_ description: PackageFrame.Description?) -> TestConfiguration? {
            switch (self, description) {
            case (.tests, .tests(let configuration)?), (.benchmarks, .benchmarks(let configuration)?):
                return configuration
            default:
                return nil
            }
        }
    }

    public static let conventionalDirectory = Kind.tests.conventional.name

    public enum RunError: Error, Sendable, LocalizedError {
        case notConfigured(URL, Kind)
        case ambiguousPrimary([URL])
        case failed(product: String, exitCode: Int32?, signal: Int32?)
        case parentReachedThroughDependencies(parent: String, dependents: [String])

        public var errorDescription: String? {
            switch self {
            case .notConfigured(let project, let kind):
                return "No \(kind.noun) package (a directory with Package.swift and package.frame declaring `\(kind.declaration)`) below \(project.path)."
            case .ambiguousPrimary(let packages):
                return "Several packages and none at the conventional directory: choose one with -p (\(packages.map(\.lastPathComponent).joined(separator: ", ")))."
            case .failed(let product, let code, let signal):
                return "Product '\(product)' failed (exit: \(String(describing: code)), signal: \(String(describing: signal)))."
            case .parentReachedThroughDependencies(let parent, let dependents):
                return "The package reaches '\(parent)' through \(dependents.joined(separator: ", ")), not only through its path dependency. Use a library outside \(parent)'s dependency graph (Testing instead of TestFlows, or none)."
            }
        }
    }

    /// A test or benchmark package found below a project.
    public struct TestPackage: Sendable, Equatable {
        public let directory: URL
        public let configuration: TestConfiguration
    }

    /// Products to run in one package, and how they build.
    public struct Run: Sendable, Equatable {
        public let package: URL
        public let products: [String]
        public let mode: Build.Config.Mode
        public init(package: URL, products: [String], mode: Build.Config.Mode = .debug) {
            self.package = package
            self.products = products
            self.mode = mode
        }
    }

    public struct Plan: Sendable {
        public let project: URL
        public let runs: [Run]
        public var products: [String] { runs.flatMap(\.products) }
        public init(project: URL, runs: [Run]) {
            self.project = project
            self.runs = runs
        }
    }

    public static func resolve(
        at project: URL,
        selection: TestConfiguration.Selection = .primary,
        kind: Kind = .tests
    ) async throws -> Plan {
        let project = project.standardizedFileURL

        // Run from inside a test or benchmark package: that package alone.
        if let configuration = kind.configuration(try description(in: project)) {
            let parent = project.deletingLastPathComponent()
            guard try BuildObjectDiscovery.local(named: "Package.swift", in: project) != nil else {
                guard kind == .tests else { throw RunError.notConfigured(parent, kind) }
                return try await unsplitPlan(at: parent, configuration: configuration, selection: selection)
            }
            let package = TestPackage(directory: project, configuration: configuration)
            return Plan(project: parent, runs: try await runs(of: [package], parent: parent, selection: selection, kind: kind))
        }

        let packages = try testPackages(in: project, kind: kind)
        if !packages.isEmpty {
            return Plan(project: project, runs: try await runs(of: packages, parent: project, selection: selection, kind: kind))
        }
        if kind == .tests,
           let configuration = kind.configuration(try description(in: PackageLayout.url(kind.conventional.root, in: project))) {
            return try await unsplitPlan(at: project, configuration: configuration, selection: selection)
        }
        if let legacy = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: project) {
            throw ConfigurationFileError.legacy(legacy)
        }
        throw RunError.notConfigured(project, kind)
    }

    /// Test (or benchmark) packages directly below a project, the conventional directory first.
    public static func testPackages(in project: URL, kind: Kind = .tests) throws -> [TestPackage] {
        let entries = try FileSystem.default.directory.entries(project, options: [.skipsHiddenFiles])
        let directories: [URL] = entries.filter { $0.kind == .directory }.map(\.url)
        let conventional = kind.conventional.name
        func order(_ directory: URL) -> String {
            directory.lastPathComponent == conventional ? "" : directory.lastPathComponent
        }
        var packages: [TestPackage] = []
        for directory in directories.sorted(by: { order($0) < order($1) }) {
            guard try BuildObjectDiscovery.local(named: "Package.swift", in: directory) != nil,
                  let configuration = kind.configuration(try description(in: directory))
            else { continue }
            packages.append(TestPackage(directory: directory.standardizedFileURL, configuration: configuration))
        }
        return packages
    }

    /// The parent may only be a direct dependency of the test package. A deeper edge means a
    /// dependency brings in the parent's remote copy, which SwiftPM unifies with the local one
    /// under a "Conflicting identity" warning it plans to turn into an error.
    public static func verifyGraph(of package: URL, parent: URL) async throws {
        let graph = try await Package.graph(at: package)
        let parentIdentity = parent.lastPathComponent.lowercased()
        let dependents = graph.edges
            .filter { $0.targetIdentity == parentIdentity && $0.sourceIdentity != graph.rootIdentity }
            .map(\.sourceIdentity)
        guard dependents.isEmpty else {
            throw RunError.parentReachedThroughDependencies(parent: parentIdentity, dependents: dependents)
        }
    }

    public static func execute(_ plan: Plan) async throws {
        for run in plan.runs {
            for product in run.products {
                print("Running \(product)…")
                let result = try await SwiftRun.run(.init(product: product, mode: run.mode), at: run.package)
                if !result.stdoutText.isEmpty { print(result.stdoutText, terminator: "") }
                if !result.stderrText.isEmpty { fputs(result.stderrText, stderr) }
                guard result.isSuccess else {
                    throw RunError.failed(product: product, exitCode: result.exitCode, signal: result.signal)
                }
            }
        }
    }
}

private extension Tests {
    static func description(in directory: URL) throws -> PackageFrame.Description? {
        guard let file = try BuildObjectDiscovery.local(named: PackageFrame.fileName, in: directory) else { return nil }
        return try PackageFrame.read(file)
    }

    /// `.primary` runs the primary of the conventional package (or of the only one); `.all`
    /// runs every package; a group or product runs wherever it is declared.
    static func runs(
        of packages: [TestPackage],
        parent: URL,
        selection: TestConfiguration.Selection,
        kind: Kind
    ) async throws -> [Run] {
        let chosen: [TestPackage]
        switch selection {
        case .primary:
            if let conventional = packages.first(where: { $0.directory.lastPathComponent == kind.conventional.name }) {
                chosen = [conventional]
            } else if packages.count == 1 {
                chosen = packages
            } else {
                throw RunError.ambiguousPrimary(packages.map(\.directory))
            }
        case .all, .product:
            chosen = packages
        case .group(let name):
            chosen = packages.filter { $0.configuration.groups[name] != nil }
            guard !chosen.isEmpty else { throw TestConfiguration.ValidationError.unknownGroup(name) }
        }

        var runs: [Run] = []
        for package in chosen {
            try await verifyGraph(of: package.directory, parent: parent)
            let available = Set(try await Products.executableNames(in: package.directory))
            if case .product(let name) = selection, !available.contains(name) { continue }
            let products = try package.configuration.selectedProducts(
                for: selection,
                availableProducts: available,
                testPackage: true
            )
            runs.append(Run(package: package.directory, products: products, mode: package.configuration.mode?.config ?? kind.mode))
        }
        if case .product(let name) = selection, runs.isEmpty {
            throw TestConfiguration.ValidationError.undeclaredProduct(name)
        }
        return runs
    }

    /// `Tests/package.frame` declares the tests, but they have not moved into a `Tests/` package
    /// yet: the declared products run from the project's own package.
    static func unsplitPlan(
        at project: URL,
        configuration: TestConfiguration,
        selection: TestConfiguration.Selection
    ) async throws -> Plan {
        let available = Set(try await Products.executableNames(in: project))
        let products = try configuration.selectedProducts(for: selection, availableProducts: available)
        return Plan(project: project, runs: [Run(package: project, products: products, mode: configuration.mode?.config ?? .debug)])
    }
}
