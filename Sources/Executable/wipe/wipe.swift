import Primitives
import Foundation
import IO
import Path

/// `sbm wipe`: delete `.build` and `.index-build`, honouring the keep list and never deleting
/// under a running build. The scope picks which packages: `all` (the package with its Tests/ and
/// Benchmarks/), `main` (the package itself) or `extra` (only Tests/ and Benchmarks/, each
/// confirmed by its package.frame). `recursive` applies the scope to every package below the
/// root. Planning is separate from removal, so a dry run is the same plan without executing it.
public enum Wipe {
    public typealias Cache = KeepEntry.Cache

    public enum Scope: String, Sendable, CaseIterable {
        case all
        case main
        case extra
    }

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
        public var scope: Scope
        public var recursive: Bool
        /// Depth below `root` searched with `recursive` (root = 0); nil for no limit.
        public var depth: Int?
        public var ignoreKeep: Bool
        public var measure: Bool

        public init(
            root: URL,
            scope: Scope = .all,
            recursive: Bool = false,
            depth: Int? = nil,
            ignoreKeep: Bool = false,
            measure: Bool = false
        ) {
            self.root = root
            self.scope = scope
            self.recursive = recursive
            self.depth = depth
            self.ignoreKeep = ignoreKeep
            self.measure = measure
        }
    }

    public static func plan(
        _ options: Options,
        keep: KeepList,
        running: (URL) -> SwiftPMBuildLock.Holder? = SwiftPMBuildLock.holder(of:)
    ) throws -> Plan {
        let root = FileSystem.default.resolve(options.root)
        let candidates = options.recursive
            ? try packages(under: root, depth: options.depth)
            : try packages(at: root)
        let packages = candidates.filter { options.scope.includes($0) }
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
        let nested = Nested.allCases
            .map { root.appendingPathComponent($0.directory, isDirectory: true) }
            .filter { FileSystem.default.exists($0.appendingPathComponent("Package.swift")) }
        return [root] + nested
    }

    /// Every directory holding a Package.swift at or below `root`, nested packages included.
    /// One PathWalker walk: symbolic links are not followed, and hidden directories (`.build`,
    /// `.index-build`, `.git`, `.swiftpm`, leftovers) are skipped.
    static func packages(under root: URL, depth: Int?) throws -> [URL] {
        let walker = PathWalker(
            root: root,
            configuration: .init(maxDepth: depth, includeHidden: false, followSymlinks: false, emitDirectories: true, emitFiles: false)
        )
        let directories = [root] + (try walker.walk()).map(\.url)
        return directories
            .filter { FileSystem.default.exists($0.appendingPathComponent("Package.swift")) }
            .map { FileSystem.default.resolve($0) }
            .sorted { $0.path < $1.path }
    }

    /// The conventional nested packages, and the package.frame binding that confirms each.
    enum Nested: CaseIterable {
        case tests
        case benchmarks

        var directory: String {
            switch self {
            case .tests: return PackageLayout().tests.name
            case .benchmarks: return PackageLayout().benchmarks.name
            }
        }

        /// The nested package `package` is, by its directory name and its package.frame binding.
        static func of(_ package: URL) -> Nested? {
            guard let nested = allCases.first(where: { $0.directory == package.lastPathComponent }),
                  let file = try? BuildObjectDiscovery.local(named: PackageFrame.fileName, in: package),
                  let description = try? PackageFrame.read(file)
            else { return nil }
            switch (nested, description) {
            case (.tests, .tests), (.benchmarks, .benchmarks): return nested
            default: return nil
            }
        }
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

    /// What a run of a plan did. `freed` is the volume's gain in available space, nil for a dry
    /// run or when the volume could not be read.
    public struct Summary: Sendable, Equatable {
        public var packages: Int
        public var deleted = 0
        public var kept = 0
        public var skipped = 0
        public var failed = 0
        public var freed: Int64?
    }

    /// Runs a plan, reporting per directory and in total. `confirm` asks before each deletion
    /// except leftovers (the CLI without -y); a refusal counts as skipped. Failed deletions are
    /// reported and counted, not thrown.
    @discardableResult
    public static func execute(
        _ plan: Plan,
        dryRun: Bool = false,
        confirm: ((String) -> Bool)? = nil,
        output: TextSink = .standard
    ) async -> Summary {
        var summary = Summary(packages: plan.packages.count)
        guard !plan.packages.isEmpty else {
            output.line("No packages under \(plan.root.path).")
            return summary
        }
        let before = try? FileSystem.default.volume(of: plan.root).available

        func label(_ item: Item) -> String {
            let relative = item.directory.path.hasPrefix(plan.root.path + "/")
                ? String(item.directory.path.dropFirst(plan.root.path.count + 1))
                : item.directory.path
            return relative + (item.size.map { " (\($0.humanBytes))" } ?? "")
        }

        for item in plan.leftovers + plan.items {
            switch item.decision {
            case .kept(let entry, let reason):
                summary.kept += 1
                output.line("→ kept \(label(item)) (keep: \(entry)\(reason.map { ", \($0)" } ?? ""))")
                continue
            case .running(let holder):
                summary.skipped += 1
                output.line("→ skipped \(label(item)): build running (\(holder.executable), pid \(holder.pid))")
                continue
            case .delete:
                break
            }

            let leftover = isLeftover(item.directory.lastPathComponent)
            if dryRun {
                output.line("would delete \(leftover ? "leftover " : "")\(label(item))")
                continue
            }
            if let confirm, !leftover, !confirm("Delete \(label(item))?") {
                summary.skipped += 1
                continue
            }
            do {
                try await remove(item)
                summary.deleted += 1
                output.line("✓ deleted \(label(item))")
            } catch {
                summary.failed += 1
                output.line("✗ \(label(item)): \(error.localizedDescription)")
            }
        }

        if dryRun {
            output.line("\(plan.packages.count) packages; would free \(plan.measuredTotal.humanBytes) (\(plan.deletions.count) directories)")
            return summary
        }
        summary.freed = before.flatMap { before in
            (try? FileSystem.default.volume(of: plan.root).available).map { max(0, $0 - before) }
        }
        output.line("\(plan.packages.count) packages: \(summary.deleted) deleted, \(summary.kept) kept, \(summary.skipped) skipped, \(summary.failed) failed; freed ≈\((summary.freed ?? 0).humanBytes)")
        return summary
    }
}

public enum WipeError: Error, Sendable, LocalizedError, Equatable {
    case not_a_package(URL)
    case not_empty(URL, remaining: Int, sample: [String])

    public var errorDescription: String? {
        switch self {
        case .not_a_package(let url):
            return "No Package.swift in \(url.path); use -r to wipe every package below it."
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

extension Wipe.Scope {
    /// `extra` takes only Tests/ and Benchmarks/ packages their package.frame confirms; `main`
    /// takes everything else.
    func includes(_ package: URL) -> Bool {
        switch self {
        case .all: return true
        case .main: return Wipe.Nested.of(package) == nil
        case .extra: return Wipe.Nested.of(package) != nil
        }
    }
}
