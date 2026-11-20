import Foundation
import IO

/// `sbm wipe`: delete `.build` and `.index-build` of one package (with its nested
/// Tests/ and Benchmarks/ packages) or of every package under a root, honouring the keep list
/// and never deleting under a running build. Planning is separate from removal, so a dry run is
/// the same plan without executing it.
public enum Wipe {
    public typealias Cache = KeepEntry.Cache

    public enum Decision: Sendable, Equatable {
        case delete
        case kept(entry: String, reason: String?)
        case running(SwiftPMBuildLock.Holder)
    }

    public struct Item: Sendable, Equatable {
        public let package: URL
        public let cache: Cache
        public let directory: URL
        public let decision: Decision
        /// Allocated bytes; measured only when the plan was asked to measure.
        public var size: Int64?
    }

    public struct Plan: Sendable, Equatable {
        public let root: URL
        public let packages: [URL]
        public var items: [Item]
        /// `*.clean-*` directories from interrupted runs, deleted whatever the keep list says.
        public var leftovers: [Item]

        public var deletions: [Item] { leftovers + items.filter { $0.decision == .delete } }
        public var measuredTotal: Int64 { deletions.compactMap(\.size).reduce(0, +) }
    }

    public struct Options: Sendable {
        public var root: URL
        public var tree: Bool
        /// Depth below `root` searched with `tree` (root = 0); nil for no limit.
        public var depth: Int?
        public var ignoreKeep: Bool
        public var measure: Bool

        public init(root: URL, tree: Bool = false, depth: Int? = nil, ignoreKeep: Bool = false, measure: Bool = false) {
            self.root = root
            self.tree = tree
            self.depth = depth
            self.ignoreKeep = ignoreKeep
            self.measure = measure
        }
    }

    static let pruned: Set<String> = [".git", ".build", ".index-build", ".swiftpm", "node_modules"]

    public static func plan(
        _ options: Options,
        keep: KeepList,
        running: (URL) -> SwiftPMBuildLock.Holder? = SwiftPMBuildLock.holder(of:)
    ) throws -> Plan {
        let root = FileSystem.default.resolve(options.root)
        let packages = options.tree
            ? try packages(under: root, depth: options.depth)
            : try packages(at: root)
        return try plan(packages, root: root, keep: options.ignoreKeep ? KeepList() : keep,
                        measure: options.measure, running: running)
    }

    /// The plan for exactly these packages (no nested ones added): what `--wipe` on build,
    /// test and bench uses for the packages the command worked in.
    public static func plan(
        _ packages: [URL],
        root: URL,
        keep: KeepList,
        measure: Bool = false,
        running: (URL) -> SwiftPMBuildLock.Holder? = SwiftPMBuildLock.holder(of:)
    ) throws -> Plan {
        var items: [Item] = []
        var leftovers: [Item] = []
        for package in packages {
            let children = try FileSystem.default.directory.entries(package).filter { $0.kind == .directory }
            for child in children where isLeftover(child.url.lastPathComponent) {
                leftovers.append(.init(package: package, cache: child.url.lastPathComponent.hasPrefix(".index-build") ? .index : .build,
                                       directory: child.url, decision: .delete))
            }
            for cache in Cache.allCases {
                let directory = package.appendingPathComponent(cache.directoryName, isDirectory: true)
                guard children.contains(where: { $0.url.lastPathComponent == cache.directoryName }) else { continue }
                let decision: Decision
                if let entry = keep.keeping(package, cache: cache) {
                    decision = .kept(entry: entry.name, reason: entry.reason)
                } else if cache == .build, let holder = running(directory) {
                    decision = .running(holder)
                } else {
                    decision = .delete
                }
                items.append(.init(package: package, cache: cache, directory: directory, decision: decision))
            }
        }

        var plan = Plan(root: root, packages: packages, items: items, leftovers: leftovers)
        if measure {
            for index in plan.items.indices where plan.items[index].decision == .delete {
                plan.items[index].size = try? FileSystem.default.size(of: plan.items[index].directory)
            }
            for index in plan.leftovers.indices {
                plan.leftovers[index].size = try? FileSystem.default.size(of: plan.leftovers[index].directory)
            }
        }
        return plan
    }

    /// The package at `root` and its nested Tests/ and Benchmarks/ packages.
    static func packages(at root: URL) throws -> [URL] {
        guard FileSystem.default.exists(root.appendingPathComponent("Package.swift")) else {
            throw WipeError.not_a_package(root)
        }
        let nested = ["Tests", "Benchmarks"]
            .map { root.appendingPathComponent($0, isDirectory: true) }
            .filter { FileSystem.default.exists($0.appendingPathComponent("Package.swift")) }
        return [root] + nested
    }

    /// Every directory holding a Package.swift at or below `root`, nested packages included.
    /// Symbolic links are not followed; caches, `.git` and other dot-directories are pruned.
    static func packages(under root: URL, depth: Int?) throws -> [URL] {
        var found: [URL] = []
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (directory, level) = queue.removeFirst()
            guard let entries = try? FileSystem.default.directory.entries(directory) else { continue }
            if entries.contains(where: { $0.kind == .file && $0.url.lastPathComponent == "Package.swift" }) {
                found.append(directory)
            }
            guard depth.map({ level < $0 }) ?? true else { continue }
            for entry in entries where entry.kind == .directory {
                let name = entry.url.lastPathComponent
                guard !name.hasPrefix("."), !pruned.contains(name), !isLeftover(name) else { continue }
                queue.append((entry.url, level + 1))
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    static func isLeftover(_ name: String) -> Bool {
        name.hasPrefix(".build.clean-") || name.hasPrefix(".index-build.clean-")
    }

    /// Renames the directory out of the way (so a build that starts now gets a fresh one), then
    /// removes it. IO's remover rescans a directory that reports ENOTEMPTY; when a writer keeps
    /// writing, the whole detached tree is retried twice more, a second apart.
    public static func remove(_ item: Item) async throws {
        let detached: URL
        if isLeftover(item.directory.lastPathComponent) {
            detached = item.directory
        } else {
            detached = item.directory.deletingLastPathComponent().appendingPathComponent(
                "\(item.cache.directoryName).clean-\(getpid())-\(UInt32.random(in: 0 ... .max))",
                isDirectory: true
            )
            try FileSystem.default.move(item.directory, to: detached)
        }

        var attempt = 0
        while true {
            do {
                try FileSystem.default.remove(detached)
                return
            } catch let error as FileSystemError where error.reason == .directory_not_empty && attempt < 2 {
                attempt += 1
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch let error as FileSystemError where error.reason == .directory_not_empty {
                let left = (try? FileSystem.default.directory.entries(detached, recursive: true)) ?? []
                throw WipeError.not_empty(detached, remaining: left.count, sample: left.prefix(5).map(\.url.path))
            }
        }
    }
}

public enum WipeError: Error, Sendable, LocalizedError, Equatable {
    case not_a_package(URL)
    case not_empty(URL, remaining: Int, sample: [String])

    public var errorDescription: String? {
        switch self {
        case .not_a_package(let url):
            return "No Package.swift in \(url.path); use --tree to clean every package below it."
        case .not_empty(let url, let remaining, let sample):
            return """
                \(url.path) still has \(remaining) entries after 3 attempts; something keeps writing there.
                \(sample.map { "    " + $0 }.joined(separator: "\n"))
                Find the writer with: lsof +D \(url.path)
                """
        }
    }
}

extension Int64 {
    /// 1.4G, 220M, 12K: what the shell `du -h` style reads like.
    var humanBytes: String {
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(self)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(self)B" : String(format: value < 10 ? "%.1f" : "%.0f", value) + units[unit]
    }
}
