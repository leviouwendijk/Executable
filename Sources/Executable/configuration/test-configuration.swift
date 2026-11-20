import Foundation

/// Test products, reusable by `sbm test` and workflows: the `tests` binding of a test
/// package's package.frame.
public struct TestConfiguration: Codable, Sendable, Equatable {
    public let primary: String?
    public let groups: [String: [String]]
    /// Products that wait for input; never run by `.all`.
    public let interactive: [String]
    /// Products that reach real services (network, credentials); run by `.live`, never by `.all`.
    public let live: [String]
    /// Overrides the kind's default (tests debug, benchmarks release).
    public let mode: BuildMode?
    /// Wipe the caches after a run when they exceed a size.
    public let wipe: WipePolicy?

    public init(
        primary: String? = nil,
        groups: [String: [String]] = [:],
        interactive: [String] = [],
        live: [String] = [],
        mode: BuildMode? = nil,
        wipe: WipePolicy? = nil
    ) {
        self.primary = primary
        self.groups = groups
        self.interactive = interactive
        self.live = live
        self.mode = mode
        self.wipe = wipe
    }

    public enum Selection: Sendable, Equatable {
        case primary
        case all
        case live
        case group(String)
        case product(String)
    }

    public enum ValidationError: Error, Sendable, Equatable, LocalizedError {
        case invalidPrimary
        case interactivePrimary(String)
        case livePrimary(String)
        case noLiveProducts
        case noPrimary([String])
        case invalidGroup(String)
        case emptyGroup(String)
        case unknownGroup(String)
        case undeclaredProduct(String)
        case unavailableProducts([String])

        public var errorDescription: String? {
            switch self {
            case .invalidPrimary: return "tests.primary must be a non-empty executable product name."
            case .interactivePrimary(let name): return "Test product '\(name)' is interactive, so it cannot be the primary."
            case .livePrimary(let name): return "Test product '\(name)' is live, so it cannot be the primary."
            case .noLiveProducts: return "No live test products: declare .live."
            case .noPrimary(let candidates):
                return candidates.isEmpty
                    ? "No primary test product: declare .primary."
                    : "No primary test product among \(candidates.joined(separator: ", ")): declare .primary."
            case .invalidGroup(let name): return "Invalid test group identifier '\(name)'. Use letters, digits and underscores."
            case .emptyGroup(let name): return "Test group '\(name)' has no products."
            case .unknownGroup(let name): return "Unknown test group '\(name)'."
            case .undeclaredProduct(let name): return "Test product '\(name)' is not declared in tests."
            case .unavailableProducts(let names): return "Declared test products are not SwiftPM executable products: \(names.joined(separator: ", "))."
            }
        }
    }

    /// Validates all declared products, not just the chosen subset.
    public func validate(availableProducts: Set<String>) throws {
        if let primary {
            guard !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidPrimary
            }
            guard !interactive.contains(primary) else { throw ValidationError.interactivePrimary(primary) }
            guard !live.contains(primary) else { throw ValidationError.livePrimary(primary) }
        }
        for (name, products) in groups {
            let scalar = Array(name.unicodeScalars)
            guard let first = scalar.first,
                  (CharacterSet.letters.contains(first) || first == "_"),
                  scalar.dropFirst().allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" })
            else { throw ValidationError.invalidGroup(name) }
            guard !products.isEmpty else { throw ValidationError.emptyGroup(name) }
        }
        let unknown = Set(declaredProducts()).subtracting(availableProducts).sorted()
        guard unknown.isEmpty else { throw ValidationError.unavailableProducts(unknown) }
    }

    /// `testPackage`: every available product is a test product (a nested test package), so
    /// undeclared products count too. Otherwise (legacy, tests among the project's own
    /// products) only declared products are tests.
    public func selectedProducts(
        for selection: Selection,
        availableProducts: Set<String>,
        testPackage: Bool = false
    ) throws -> [String] {
        try validate(availableProducts: availableProducts)
        switch selection {
        case .primary:
            if let primary { return [primary] }
            let candidates = testPackage ? availableProducts.subtracting(interactive).subtracting(live).sorted() : []
            guard candidates.count == 1 else { throw ValidationError.noPrimary(candidates) }
            return candidates
        case .all:
            let pool = testPackage ? Self.unique(declaredProducts() + availableProducts.sorted()) : declaredProducts()
            return pool.filter { !interactive.contains($0) && !live.contains($0) }
        case .live:
            guard !live.isEmpty else { throw ValidationError.noLiveProducts }
            return Self.unique(live)
        case .group(let name):
            guard let products = groups[name] else { throw ValidationError.unknownGroup(name) }
            return Self.unique(products)
        case .product(let name):
            guard declaredProducts().contains(name) || (testPackage && availableProducts.contains(name)) else {
                throw ValidationError.undeclaredProduct(name)
            }
            return [name]
        }
    }

    private func declaredProducts() -> [String] {
        Self.unique((primary.map { [$0] } ?? []) + groups.keys.sorted().flatMap { groups[$0] ?? [] } + interactive + live)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
