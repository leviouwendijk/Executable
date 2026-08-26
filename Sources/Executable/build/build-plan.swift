import Foundation

public extension Build {
    struct Plan: Sendable {
        public let request: Request
        public let executableProducts: [ExecutableProduct]
        public let executableTargets: [ExecutableTarget]
        public let selectedProducts: [ExecutableProduct]
        public let perProductDestinations: [String: URL]

        public var selectedProductNames: [String] {
            selectedProducts.map(\.name)
        }

        public init(
            request: Request,
            executableProducts: [ExecutableProduct],
            executableTargets: [ExecutableTarget],
            selectedProducts: [ExecutableProduct],
            perProductDestinations: [String: URL]
        ) {
            self.request = request
            self.executableProducts = executableProducts
            self.executableTargets = executableTargets
            self.selectedProducts = selectedProducts
            self.perProductDestinations = perProductDestinations
        }
    }

    struct ExecutionResult: Sendable {
        public let plan: Plan
        public let build: BuildResult

        public init(
            plan: Plan,
            build: BuildResult
        ) {
            self.plan = plan
            self.build = build
        }
    }

    enum ResolutionError:
        Error,
        Sendable,
        LocalizedError,
        Equatable
    {
        case unknownProducts([String])
        case unknownTargets([String])
        case unknownSkippedProducts([String])
        case unknownSkippedTargets([String])

        public var errorDescription: String? {
            switch self {
            case .unknownProducts(let names):
                return "Unknown executable product(s): \(names.joined(separator: ", "))."

            case .unknownTargets(let names):
                return "Unknown executable target(s): \(names.joined(separator: ", ")). If this is a product name, use --products."

            case .unknownSkippedProducts(let names):
                return "Unknown executable product(s) in --skip-products: \(names.joined(separator: ", "))."

            case .unknownSkippedTargets(let names):
                return "Unknown executable target(s) in --skip-targets: \(names.joined(separator: ", "))."
            }
        }
    }
}
