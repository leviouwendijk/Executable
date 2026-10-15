import Foundation

/// Resolves registered executable test products without using a separate SwiftPM runner.
public enum Tests {
    public enum RunError: Error, Sendable, LocalizedError {
        case notConfigured(URL)
        case failed(product: String, exitCode: Int32?, signal: Int32?)

        public var errorDescription: String? {
            switch self {
            case .notConfigured(let project):
                return "No tests { } declaration in \(project.appendingPathComponent("build-object.pkl").path)."
            case .failed(let product, let code, let signal):
                return "Test product '\(product)' failed (exit: \(String(describing: code)), signal: \(String(describing: signal)))."
            }
        }
    }

    public struct Plan: Sendable {
        public let project: URL
        public let products: [String]
        public init(project: URL, products: [String]) {
            self.project = project
            self.products = products
        }
    }

    public static func resolve(
        at project: URL,
        selection: TestConfiguration.Selection = .primary
    ) async throws -> Plan {
        let project = project.standardizedFileURL
        let source = try BuildObjectDiscovery.requireLocal(named: "build-object.pkl", in: project)
        let configuration = try BuildObjectConfiguration(from: source)
        guard let tests = configuration.tests else { throw RunError.notConfigured(project) }
        let available = Set(try await Products.executableNames(in: project))
        let products = try tests.selectedProducts(for: selection, availableProducts: available)
        return Plan(project: project, products: products)
    }

    public static func execute(_ plan: Plan) async throws {
        for product in plan.products {
            print("Testing \(product)…")
            let result = try await SwiftRun.run(.init(product: product), at: plan.project)
            if !result.stdoutText.isEmpty { print(result.stdoutText, terminator: "") }
            if !result.stderrText.isEmpty { fputs(result.stderrText, stderr) }
            guard result.isSuccess else {
                throw RunError.failed(product: product, exitCode: result.exitCode, signal: result.signal)
            }
        }
    }
}
