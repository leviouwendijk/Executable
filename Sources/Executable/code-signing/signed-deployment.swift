import Foundation

public enum SignedDeployment {
    public struct Request: Sendable, Hashable {
        public let project: URL
        public let configuration: Build.Config.Mode
        public let product: String
        public let destination: URL
        public let signer: CodeSigning.Signer
        public let identifier: String?
        public let entitlements: URL?
        public let hardenedRuntime: Bool

        public init(
            project: URL,
            configuration: Build.Config.Mode,
            product: String,
            destination: URL = Build.defaultDeploymentDirectory,
            signer: CodeSigning.Signer,
            identifier: String? = nil,
            entitlements: URL? = nil,
            hardenedRuntime: Bool = false
        ) {
            self.project = project.standardizedFileURL
            self.configuration = configuration
            self.product = product
            self.destination = destination.standardizedFileURL
            self.signer = signer
            self.identifier = identifier
            self.entitlements = entitlements?.standardizedFileURL
            self.hardenedRuntime = hardenedRuntime
        }
    }

    public struct Plan: Sendable, Hashable {
        public let request: Request
        public let sourceExecutable: URL
        public let deployedExecutable: URL

        public init(
            request: Request,
            sourceExecutable: URL,
            deployedExecutable: URL
        ) {
            self.request = request
            self.sourceExecutable = sourceExecutable.standardizedFileURL
            self.deployedExecutable = deployedExecutable.standardizedFileURL
        }
    }

    public struct Result: Sendable, Hashable {
        public let plan: Plan
        public let sourceSigning: CodeSigning.SignResult
        public let deployedVerification: CodeSigning.Verification
        public let deployedInspection: CodeSigning.Inspection
    }

    public static func plan(_ request: Request) throws -> Plan {
        let buildDirectory = request.project
            .appendingPathComponent(
                ".build/\(Build.Config(mode: request.configuration).buildDirComponent)",
                isDirectory: true
            )

        let sourceExecutable = buildDirectory.appendingPathComponent(
            request.product,
            isDirectory: false
        )
        let deployedExecutable = request.destination.appendingPathComponent(
            request.product,
            isDirectory: false
        )

        guard FileManager.default.fileExists(atPath: sourceExecutable.path) else {
            throw SignedDeploymentError.builtProductNotFound(sourceExecutable)
        }

        return Plan(
            request: request,
            sourceExecutable: sourceExecutable,
            deployedExecutable: deployedExecutable
        )
    }

    public static func execute(_ plan: Plan) async throws -> Result {
        let request = plan.request
        let sourceSigning = try await CodeSigning.sign(
            .init(
                target: plan.sourceExecutable,
                signer: request.signer,
                identifier: request.identifier,
                entitlements: request.entitlements,
                hardenedRuntime: request.hardenedRuntime
            )
        )

        try Deploy.selected(
            from: request.project,
            config: .init(mode: request.configuration),
            to: request.destination,
            products: [request.product],
            perProductDestinations: [:]
        )

        let deployedVerification = try await CodeSigning.verify(
            plan.deployedExecutable
        )
        guard deployedVerification.valid else {
            throw SignedDeploymentError.deployedSignatureInvalid(
                target: plan.deployedExecutable,
                output: deployedVerification.output
            )
        }

        return Result(
            plan: plan,
            sourceSigning: sourceSigning,
            deployedVerification: deployedVerification,
            deployedInspection: try await CodeSigning.inspect(
                plan.deployedExecutable
            )
        )
    }
}

public enum SignedDeploymentError: Error, Sendable, LocalizedError, Equatable {
    case builtProductNotFound(URL)
    case deployedSignatureInvalid(target: URL, output: String)

    public var errorDescription: String? {
        switch self {
        case .builtProductNotFound(let target):
            "Built executable product not found: \(target.path)"
        case .deployedSignatureInvalid(let target, let output):
            "Deployed executable has an invalid code signature at \(target.path): \(output)"
        }
    }
}
