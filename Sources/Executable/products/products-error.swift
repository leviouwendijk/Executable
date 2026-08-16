import Foundation

public enum ProductsError:
    Error,
    LocalizedError,
    Sendable
{
    case noExecutableProductsFound

    public var errorDescription: String? {
        switch self {
        case .noExecutableProductsFound:
            "No executable products found"
        }
    }

    public var failureReason: String? {
        switch self {
        case .noExecutableProductsFound:
            "The package declares no executable products."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noExecutableProductsFound:
            "Add an executable product or choose a different package directory."
        }
    }
}
