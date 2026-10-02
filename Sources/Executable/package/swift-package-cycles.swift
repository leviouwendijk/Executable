import Foundation
import Path
import Primitives

/// Result of scanning declared package dependencies for cycles.
public struct SwiftPackageCycleReport: Sendable, Hashable {
    /// Identity of the scanned root package.
    public let root: String

    /// Identities reachable from the root, in walk order.
    public let packages: [String]

    /// Declared dependencies per reachable identity.
    public let dependencies: [String: [String]]

    /// Dependency loops, each starting at its alphabetically first member.
    /// At least one cycle is reported per loop; overlapping loops through
    /// the same packages may be reported only once.
    public let cycles: [[String]]

    /// Checkouts whose manifest SwiftPM could not evaluate.
    public let unreadableManifests: [String]

    public var hasCycles: Bool {
        !cycles.isEmpty
    }

    public init(
        root: String,
        packages: [String],
        dependencies: [String: [String]],
        cycles: [[String]],
        unreadableManifests: [String]
    ) {
        self.root = root
        self.packages = packages
        self.dependencies = dependencies
        self.cycles = cycles
        self.unreadableManifests = unreadableManifests
    }
}

/// Finds package-level dependency cycles without asking SwiftPM to walk
/// the package graph.
///
/// A package cycle can make SwiftPM overflow its stack wherever it walks
/// the whole graph (`swift package show-dependencies`, preparing a
/// build-tool plugin). This check therefore evaluates each manifest on its
/// own with `swift package dump-package`, which loads a single manifest and
/// never resolves the graph, and does the graph walk itself.
///
/// Manifests are read from the root package plus every checkout under
/// `.build/checkouts`, so the result reflects the revisions SwiftPM
/// resolved. Run `swift package resolve` first if there are no checkouts.
public enum SwiftPackageCycles {
    private static let concurrentManifestLoads = 6

    public static func scan(
        packageDirectory: URL
    ) async throws -> SwiftPackageCycleReport {
        let root = packageDirectory.lastPathComponent.lowercased()
        let rootManifest = try await Package.manifest(
            at: packageDirectory
        )

        let checkouts = try checkoutDirectories(
            of: packageDirectory
        )
        let loaded = await loadDependencies(
            ofCheckouts: checkouts
        )

        var dependencies: [String: [String]] = [:]
        var unreadable: [String] = []

        for entry in loaded {
            guard let declared = entry.dependencies else {
                unreadable.append(
                    entry.name
                )
                continue
            }

            dependencies[entry.name.lowercased()] = declared
        }

        dependencies[root] = identities(
            declaredBy: rootManifest,
            excluding: root
        )

        let traversal = try cycles(
            from: root,
            dependencies: dependencies
        )

        var reachableDependencies: [String: [String]] = [:]

        for identity in traversal.reachable {
            reachableDependencies[identity] = dependencies[identity] ?? []
        }

        return SwiftPackageCycleReport(
            root: root,
            packages: traversal.reachable,
            dependencies: reachableDependencies,
            cycles: traversal.cycles,
            unreadableManifests: unreadable.sorted()
        )
    }

    /// Walks the declared-dependency graph from `root` with
    /// `Primitives.TreeExpansion`. The walk is iterative and visits every
    /// package once; a dependency that points back at one of its own
    /// ancestors is recorded as a cycle instead of being followed.
    static func cycles(
        from root: String,
        dependencies: [String: [String]]
    ) throws -> (
        reachable: [String],
        cycles: [[String]]
    ) {
        struct Visit: Hashable {
            let identity: String
            let path: [String]
        }

        var found = Set<[String]>()

        let expansion = TreeExpansion<Visit>(
            roots: [
                Visit(
                    identity: root,
                    path: [root]
                )
            ],
            children: { located in
                let visit = located.value
                var next: [Visit] = []

                for dependency in dependencies[visit.identity] ?? [] {
                    if let index = visit.path.firstIndex(of: dependency) {
                        found.insert(
                            canonical(
                                Array(visit.path[index...])
                            )
                        )
                        continue
                    }

                    next.append(
                        Visit(
                            identity: dependency,
                            path: visit.path + [dependency]
                        )
                    )
                }

                return next
            }
        )

        let revisit = TreeExpansionRevisitPolicy<Visit>.global(
            action: .skip,
            identity: { visit in
                visit.identity
            }
        )

        var iterator = expansion
            .walk(
                .depth_first_preorder,
                revisit: revisit
            )
            .makeIterator()

        var reachable: [String] = []

        while let located = try iterator.next() {
            reachable.append(
                located.value.identity
            )
        }

        let ordered = found.sorted { lhs, rhs in
            lhs.joined(separator: "/") < rhs.joined(separator: "/")
        }

        return (
            reachable: reachable,
            cycles: ordered
        )
    }

    /// Package identities a manifest declares, as SwiftPM reported them.
    static func identities(
        declaredBy manifest: SwiftPackageManifest,
        excluding own: String
    ) -> [String] {
        var identities = Set<String>()

        for dependency in manifest.dependencies {
            let name: String

            if let identity = dependency.identity,
               !identity.isEmpty {
                name = identity.lowercased()
            } else if let location = dependency.location {
                name = identity(
                    forLocation: location
                )
            } else {
                continue
            }

            guard !name.isEmpty,
                  name != own
            else {
                continue
            }

            identities.insert(name)
        }

        return identities.sorted()
    }

    static func identity(
        forLocation location: String
    ) -> String {
        var trimmed = location

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        var last = String(
            trimmed
                .split(separator: "/")
                .last ?? ""
        )

        if last.lowercased().hasSuffix(".git") {
            last.removeLast(4)
        }

        return last.lowercased()
    }

    private static func checkoutDirectories(
        of packageDirectory: URL
    ) throws -> [URL] {
        let checkouts = packageDirectory
            .appendingPathComponent(
                ".build",
                isDirectory: true
            )
            .appendingPathComponent(
                "checkouts",
                isDirectory: true
            )

        guard FileManager.default.fileExists(atPath: checkouts.path) else {
            return []
        }

        let result = try PathScan.scan(
            PathScanSpecification(
                includes: [
                    PathExpression(
                        pattern: PathPattern(
                            .any
                        )
                    )
                ]
            ),
            relativeTo: .directoryURL(checkouts),
            configuration: .init(
                emitFiles: false
            )
        )

        return result.matches
            .filter { match in
                match.type == .directory
            }
            .map { match in
                match.url
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent < rhs.lastPathComponent
            }
    }

    private static func loadDependencies(
        ofCheckouts directories: [URL]
    ) async -> [(name: String, dependencies: [String]?)] {
        await withTaskGroup(
            of: (String, [String]?).self
        ) { group -> [(name: String, dependencies: [String]?)] in
            var collected: [(name: String, dependencies: [String]?)] = []
            var pending = directories.makeIterator()
            var started = 0

            while started < concurrentManifestLoads,
                  let directory = pending.next() {
                group.addTask {
                    await declaredDependencies(
                        ofCheckout: directory
                    )
                }
                started += 1
            }

            while let finished = await group.next() {
                collected.append(
                    (
                        name: finished.0,
                        dependencies: finished.1
                    )
                )

                if let directory = pending.next() {
                    group.addTask {
                        await declaredDependencies(
                            ofCheckout: directory
                        )
                    }
                }
            }

            return collected
        }
    }

    private static func declaredDependencies(
        ofCheckout directory: URL
    ) async -> (String, [String]?) {
        let name = directory.lastPathComponent

        guard let manifest = try? await Package.manifest(
            at: directory
        ) else {
            return (
                name,
                nil
            )
        }

        return (
            name,
            identities(
                declaredBy: manifest,
                excluding: name.lowercased()
            )
        )
    }

    private static func canonical(
        _ cycle: [String]
    ) -> [String] {
        guard let smallest = cycle.min(),
              let index = cycle.firstIndex(of: smallest)
        else {
            return cycle
        }

        return Array(cycle[index...] + cycle[..<index])
    }
}
