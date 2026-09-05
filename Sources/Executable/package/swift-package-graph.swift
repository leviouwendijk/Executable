import Foundation

/// Resolved SwiftPM package topology plus the root package's manifest declaration.
///
/// Package nodes and edges come from `swift package show-dependencies --format json`.
/// Product and target declarations remain authoritative in `manifest`; this graph
/// does not invent product/module relationships for transitive packages.
public struct SwiftPackageGraph:
    Sendable,
    Hashable
{
    public struct PackageNode:
        Sendable,
        Hashable
    {
        public let identity: String
        public let name: String
        public let location: String?
        public let version: String?
        public let path: String?

        public init(
            identity: String,
            name: String,
            location: String? = nil,
            version: String? = nil,
            path: String? = nil
        ) {
            self.identity = identity
            self.name = name
            self.location = location
            self.version = version
            self.path = path
        }
    }

    public struct Edge:
        Sendable,
        Hashable
    {
        public let sourceIdentity: String
        public let targetIdentity: String

        public init(
            sourceIdentity: String,
            targetIdentity: String
        ) {
            self.sourceIdentity = sourceIdentity
            self.targetIdentity = targetIdentity
        }
    }

    public let rootIdentity: String
    public let manifest: SwiftPackageManifest
    public let packages: [PackageNode]
    public let edges: [Edge]

    public init(
        rootIdentity: String,
        manifest: SwiftPackageManifest,
        packages: [PackageNode],
        edges: [Edge]
    ) {
        self.rootIdentity = rootIdentity
        self.manifest = manifest
        self.packages = packages.sorted {
            packageKey($0) < packageKey($1)
        }
        self.edges = edges.sorted {
            edgeKey($0) < edgeKey($1)
        }
    }

    public var rootPackage: PackageNode? {
        package(
            identifiedBy: rootIdentity
        )
    }

    public func package(
        identifiedBy identity: String
    ) -> PackageNode? {
        packages.first {
            $0.identity == identity
        }
    }
}

extension SwiftPackageGraph {
    init(
        dependencyData: Data,
        manifest: SwiftPackageManifest
    ) throws {
        let root = try JSONDecoder().decode(
            SwiftPackageGraphDumpNode.self,
            from: dependencyData
        )

        var nodes: [String: PackageNode] = [:]
        var edges = Set<Edge>()

        func visit(
            _ node: SwiftPackageGraphDumpNode
        ) {
            let identity = node.resolvedIdentity

            nodes[identity] = PackageNode(
                identity: identity,
                name: node.name ?? identity,
                location: node.url,
                version: node.version,
                path: node.path
            )

            for dependency in node.dependencies ?? [] {
                let dependencyIdentity =
                    dependency.resolvedIdentity

                edges.insert(
                    .init(
                        sourceIdentity: identity,
                        targetIdentity:
                            dependencyIdentity
                    )
                )

                visit(
                    dependency
                )
            }
        }

        visit(
            root
        )

        self.init(
            rootIdentity: root.resolvedIdentity,
            manifest: manifest,
            packages: Array(
                nodes.values
            ),
            edges: Array(
                edges
            )
        )
    }
}

private struct SwiftPackageGraphDumpNode:
    Decodable
{
    let identity: String?
    let name: String?
    let url: String?
    let version: String?
    let path: String?
    let dependencies: [Self]?

    var resolvedIdentity: String {
        if let identity,
           !identity.isEmpty
        {
            return identity
        }

        if let name,
           !name.isEmpty
        {
            return name.lowercased()
        }

        if let url,
           let component = url
                .split(separator: "/")
                .last
                .map(String.init),
           !component.isEmpty
        {
            return component
                .replacingOccurrences(
                    of: ".git",
                    with: ""
                )
                .lowercased()
        }

        return "unknown"
    }
}

private func packageKey(
    _ package: SwiftPackageGraph.PackageNode
) -> String {
    [
        package.identity,
        package.name,
        package.location ?? "",
        package.version ?? "",
        package.path ?? "",
    ]
        .joined(
            separator: "\u{1F}"
        )
}

private func edgeKey(
    _ edge: SwiftPackageGraph.Edge
) -> String {
    edge.sourceIdentity
        + "\u{1F}"
        + edge.targetIdentity
}
