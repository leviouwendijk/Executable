import Foundation

public extension Build {
    struct Signing: Sendable {
        public let defaultConfiguration: CodeSigning.Configuration?
        public let products: [String: CodeSigning.Configuration]

        public init(
            defaultConfiguration: CodeSigning.Configuration? = nil,
            products: [String: CodeSigning.Configuration] = [:]
        ) {
            self.defaultConfiguration = defaultConfiguration
            self.products = products
        }

        public var requiresResolution: Bool {
            defaultConfiguration != nil || !products.isEmpty
        }

        public func configuration(
            for productName: String
        ) -> CodeSigning.Configuration? {
            products[productName] ?? defaultConfiguration
        }
    }

    struct ProductSigningResult: Sendable {
        public let product: String
        public let source: CodeSigning.SignResult
        public let deployedVerification: CodeSigning.Verification?
        public let deployedInspection: CodeSigning.Inspection?

        public init(
            product: String,
            source: CodeSigning.SignResult,
            deployedVerification: CodeSigning.Verification?,
            deployedInspection: CodeSigning.Inspection?
        ) {
            self.product = product
            self.source = source
            self.deployedVerification = deployedVerification
            self.deployedInspection = deployedInspection
        }
    }

    enum SigningError:
        Error,
        Sendable,
        LocalizedError,
        Equatable
    {
        case deployedSignatureInvalid(
            product: String,
            target: URL,
            output: String
        )

        public var errorDescription: String? {
            switch self {
            case .deployedSignatureInvalid(
                let product,
                let target,
                let output
            ):
                "Deployed product '\(product)' has an invalid code signature at \(target.path): \(output)"
            }
        }
    }
}
