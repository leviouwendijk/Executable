import Foundation

/// Declared SwiftPM executable test products, reusable by `sbm test` and workflows.
public struct TestConfiguration: Codable, Sendable, Equatable {
    public let primary: String
    public let groups: [String: [String]]

    public init(primary: String, groups: [String: [String]] = [:]) {
        self.primary = primary
        self.groups = groups
    }

    public enum Selection: Sendable, Equatable {
        case primary
        case all
        case group(String)
        case product(String)
    }

    public enum ValidationError: Error, Sendable, Equatable, LocalizedError {
        case invalidPrimary
        case invalidGroup(String)
        case emptyGroup(String)
        case unknownGroup(String)
        case undeclaredProduct(String)
        case unavailableProducts([String])

        public var errorDescription: String? {
            switch self {
            case .invalidPrimary: return "tests.primary must be a non-empty executable product name."
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
        guard !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidPrimary
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

    public func selectedProducts(
        for selection: Selection,
        availableProducts: Set<String>
    ) throws -> [String] {
        try validate(availableProducts: availableProducts)
        switch selection {
        case .primary: return [primary]
        case .all: return declaredProducts()
        case .group(let name):
            guard let products = groups[name] else { throw ValidationError.unknownGroup(name) }
            return Self.unique(products)
        case .product(let name):
            guard declaredProducts().contains(name) else { throw ValidationError.undeclaredProduct(name) }
            return [name]
        }
    }

    public func contents() -> String {
        var lines = ["tests {", "    primary = \(PklText.quote(primary))"]
        if !groups.isEmpty {
            lines.append("    groups {")
            for name in groups.keys.sorted() {
                lines.append(PklText.collection(name, values: groups[name] ?? [], indent: 2))
            }
            lines.append("    }")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func declaredProducts() -> [String] {
        Self.unique([primary] + groups.keys.sorted().flatMap { groups[$0] ?? [] })
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
