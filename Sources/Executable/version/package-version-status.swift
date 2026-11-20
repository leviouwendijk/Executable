import Foundation
import Version

/// Whether a project's products are current: deployed products against the newest release tag
/// (their metadata in the deploy directory), local products against HEAD (their build record in
/// `.build/<mode>/`).
public struct PackageVersionStatus: Sendable {
    public struct Product: Sendable, Equatable {
        public let product: String
        public let metadata: ProductMetadata?
    }

    public let release: ObjectVersion?
    public let head: BuildIdentity?
    public let deployed: [Product]
    /// Products built without deploying (`localProducts`), with their build records.
    public let built: [Product]

    /// A deployed product is behind when it was never deployed with an identity, or when its
    /// version is below the released one (without a release: when its commit is not HEAD).
    /// A local product is behind when no build recorded it, or its recorded commit is not HEAD,
    /// so pulling new commits is enough to rebuild it; no release is needed.
    public var behind: [String] {
        let deployedBehind = deployed.filter { entry in
            guard let metadata = entry.metadata, let commit = metadata.commit else { return true }
            guard let release else { return commit != head?.commit }
            guard let built = metadata.version else { return true }
            return built < release
        }
        let builtBehind = built.filter { entry in
            guard let commit = entry.metadata?.commit else { return true }
            return commit != head?.commit
        }
        return (deployedBehind + builtBehind).map(\.product)
    }

    public static func inspect(
        at project: URL,
        configuration: PackageConfiguration,
        deployedTo root: URL = Build.defaultDeploymentDirectory
    ) async throws -> PackageVersionStatus {
        let head = await BuildIdentity.current(at: project)
        let deployed = try (configuration.deployProducts ?? []).map { product in
            Product(product: product, metadata: try ProductMetadata.read(product: product, in: root))
        }
        let records = BuildRecord.directory(project: project, mode: (configuration.mode ?? .release).config)
        let built = try configuration.localProducts.map { product in
            Product(product: product, metadata: try ProductMetadata.read(product: product, in: records))
        }
        return .init(release: head?.version, head: head, deployed: deployed, built: built)
    }
}
