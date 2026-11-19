import Foundation
import IO

/// Resolves and runs executable test products without a separate SwiftPM runner.
///
/// Test packages are nested packages directly below a project: a directory with a
/// Package.swift (depending on the project by path) and a package.frame declaring
/// `let tests: Tests`. `Tests/` is the conventional one; others (`Benchmarks/`) work the
/// same way. Projects not yet split keep their test products in the root package, declared
/// in build-object.pkl `tests { }`.
public enum Tests {
    public static let conventionalDirectory = "Tests"

    public enum RunError: Error, Sendable, LocalizedError {
        case notConfigured(URL)
        case ambiguousPrimary([URL])
        case failed(product: String, exitCode: Int32?, signal: Int32?)
        case parentReachedThroughDependencies(parent: String, dependents: [String])

        public var errorDescription: String? {
            switch self {
            case .notConfigured(let project):
                return "No test package (a directory with Package.swift and package.frame declaring `let tests: Tests`) below \(project.path), and no legacy tests { } declaration."
            case .ambiguousPrimary(let packages):
                return "Several test packages and none at Tests/: choose one with -p (\(packages.map(\.lastPathComponent).joined(separator: ", ")))."
            case .failed(let product, let code, let signal):
                return "Test product '\(product)' failed (exit: \(String(describing: code)), signal: \(String(describing: signal)))."
            case .parentReachedThroughDependencies(let parent, let dependents):
                return "The test package reaches '\(parent)' through \(dependents.joined(separator: ", ")), not only through its path dependency. Test with a library outside \(parent)'s dependency graph (Testing instead of TestFlows, or none)."
            }
        }
    }

    /// A test package found below a project.
    public struct TestPackage: Sendable, Equatable {
        public let directory: URL
        public let configuration: TestConfiguration
    }

    /// Products to run in one package.
    public struct Run: Sendable, Equatable {
        public let package: URL
        public let products: [String]
        public init(package: URL, products: [String]) {
            self.package = package
            self.products = products
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
        selection: TestConfiguration.Selection = .primary
    ) async throws -> Plan {
        let project = project.standardizedFileURL

        // Run from inside a test package: that package alone.
        if case .tests(let configuration)? = try description(in: project) {
            let parent = project.deletingLastPathComponent()
            let package = TestPackage(directory: project, configuration: configuration)
            return Plan(project: parent, runs: try await runs(of: [package], parent: parent, selection: selection))
        }

        let packages = try testPackages(in: project)
        guard !packages.isEmpty else { return try await legacyPlan(at: project, selection: selection) }
        return Plan(project: project, runs: try await runs(of: packages, parent: project, selection: selection))
    }

    /// Test packages directly below a project, `Tests/` first.
    public static func testPackages(in project: URL) throws -> [TestPackage] {
        let entries = try FileSystem.default.directory.entries(project, options: [.skipsHiddenFiles])
        let directories: [URL] = entries.filter { $0.kind == .directory }.map(\.url)
        var packages: [TestPackage] = []
        for directory in directories.sorted(by: { order($0) < order($1) }) {
            guard try BuildObjectDiscovery.local(named: "Package.swift", in: directory) != nil,
                  case .tests(let configuration)? = try description(in: directory)
            else { continue }
            packages.append(TestPackage(directory: directory.standardizedFileURL, configuration: configuration))
        }
        return packages
    }

    /// `Tests/` sorts first, the rest by name.
    private static func order(_ directory: URL) -> String {
        directory.lastPathComponent == conventionalDirectory ? "" : directory.lastPathComponent
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
                print("Testing \(product)…")
                let result = try await SwiftRun.run(.init(product: product), at: run.package)
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

    /// `.primary` runs the primary of `Tests/` (or of the only test package); `.all` runs every
    /// package; a group or product runs wherever it is declared.
    static func runs(
        of packages: [TestPackage],
        parent: URL,
        selection: TestConfiguration.Selection
    ) async throws -> [Run] {
        let chosen: [TestPackage]
        switch selection {
        case .primary:
            if let conventional = packages.first(where: { $0.directory.lastPathComponent == conventionalDirectory }) {
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
            runs.append(Run(package: package.directory, products: products))
        }
        if case .product(let name) = selection, runs.isEmpty {
            throw TestConfiguration.ValidationError.undeclaredProduct(name)
        }
        return runs
    }

    static func legacyPlan(
        at project: URL,
        selection: TestConfiguration.Selection
    ) async throws -> Plan {
        guard let legacy = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: project),
              let tests = try BuildObjectConfiguration(from: legacy).tests
        else { throw RunError.notConfigured(project) }
        let available = Set(try await Products.executableNames(in: project))
        let products = try tests.selectedProducts(for: selection, availableProducts: available)
        return Plan(project: project, runs: [Run(package: project, products: products)])
    }
}
