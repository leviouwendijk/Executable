import Foundation
import Path

/// Where the parts of a package live, relative to its repository root:
///
///     Package.swift, package.frame
///     Sources/<Target>/
///     Tests/        a nested package: Package.swift, package.frame, Sources/, Fixtures/
///     Benchmarks/   a nested package: Package.swift, package.frame, Sources/, Results/
public struct PackageLayout: Sendable {
    public let root: PathTreeDirectoryAddress

    public init(root: PathTreeDirectoryAddress = .root) {
        self.root = root
    }

    public var manifest: PathTreeFileAddress { root.file("Package.swift") }
    public var description: PathTreeFileAddress { root.file(PackageFrame.fileName) }
    public var sources: PathTreeDirectoryAddress { root.directory("Sources") }
    public var tests: Nested { .init(root: root.directory("Tests")) }
    public var benchmarks: Nested { .init(root: root.directory("Benchmarks")) }

    /// A package nested in the repository (Tests/, Benchmarks/), with its own manifest.
    public struct Nested: Sendable {
        public let root: PathTreeDirectoryAddress

        public var manifest: PathTreeFileAddress { root.file("Package.swift") }
        public var description: PathTreeFileAddress { root.file(PackageFrame.fileName) }
        public var sources: PathTreeDirectoryAddress { root.directory("Sources") }
        public var fixtures: PathTreeDirectoryAddress { root.directory("Fixtures") }
        public var results: PathTreeDirectoryAddress { root.directory("Results") }

        /// The directory name below the repository root.
        public var name: String { root.renderedPath }
    }

    /// The location of an address inside a project directory.
    public static func url<Kind>(_ address: PathTreeAddress<Kind>, in project: URL) -> URL {
        address.path.segments.reduce(project) { url, segment in
            url.appendingPathComponent(segment.value)
        }
    }
}
