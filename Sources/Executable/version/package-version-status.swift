import Foundation
import Version

/// Versions of a package.frame project: the released tag, HEAD, and what each deployed
/// product was last built from.
public struct PackageVersionStatus: Sendable {
    public struct Deployed: Sendable, Equatable {
        public let product: String
        public let metadata: DeployedMetadata?
    }

    public let release: ObjectVersion?
    public let head: BuildIdentity?
    public let deployed: [Deployed]

    /// A deployed product is behind when it was never deployed with an identity, or when its
    /// version is below the released one. Without `.deploy`, nothing is ever behind.
    public var behind: [String] {
        deployed.filter { entry in
            guard let metadata = entry.metadata, let commit = metadata.commit else { return true }
            guard let release else { return commit != head?.commit }
            guard let built = metadata.version else { return true }
            return built < release
        }
        .map(\.product)
    }

    public static func inspect(
        at project: URL,
        configuration: PackageConfiguration,
        deployedTo root: URL = Build.defaultDeploymentDirectory
    ) async throws -> PackageVersionStatus {
        let head = await BuildIdentity.current(at: project)
        let deployed = try (configuration.deployProducts ?? []).map { product in
            Deployed(product: product, metadata: try DeployedMetadata.read(product: product, in: root))
        }
        return .init(release: head?.version, head: head, deployed: deployed)
    }
}
