import Foundation

public enum SwiftRunError:
    Error,
    Sendable,
    LocalizedError
{
    case productNotFound(
        product: String,
        available: [String]
    )

    public var errorDescription: String? {
        switch self {
        case .productNotFound(
            let product,
            let available
        ):
            let renderedAvailable =
                available.isEmpty
                ? "<none>"
                : available.joined(
                    separator: ", "
                )

            return """
            Swift executable product '\(product)' was not found. Available products: \(renderedAvailable)
            """
        }
    }
}
