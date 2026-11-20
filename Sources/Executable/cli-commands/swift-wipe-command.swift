import Arguments
import Foundation
import IO
import Processes
import Terminal

public enum SwiftWipeCommand: ArgumentCommand {
    public static let name = "wipe"
    public static let defaultChild = SwiftWipeAllCommand.self

    public static let children: [ArgumentCommandType] = [
        SwiftWipeAllCommand.self,
        SwiftWipeMainCommand.self,
        SwiftWipeExtraCommand.self,
        SwiftWipeCachesCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Delete .build and .index-build: all (default), main (the package only), extra (Tests/ and Benchmarks/ only); -r for every package below. caches: SwiftPM's global cache."
            ),
        ]
    }
}

/// `sbm wipe [all]`: the package with its Tests/ and Benchmarks/.
public enum SwiftWipeAllCommand: BoundArgumentCommand {
    public static let name = "all"

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Delete .build and .index-build of the package and its Tests/ and Benchmarks/ (-r: every package below). Other scopes: sbm wipe main (the package only), sbm wipe extra (Tests/ and Benchmarks/ only), sbm wipe caches (SwiftPM's global cache)."),
         try params(SwiftWipePackageCommand.Options.self)]
    }

    public static func run(_ options: SwiftWipePackageCommand.Options, invocation: ParsedInvocation) async throws {
        try await SwiftWipePackageCommand.run(options, scope: .all)
    }
}

/// `sbm wipe main`: the package itself, leaving Tests/ and Benchmarks/.
public enum SwiftWipeMainCommand: BoundArgumentCommand {
    public static let name = "main"

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Delete .build and .index-build of the package itself, not its Tests/ and Benchmarks/ (-r: every main package below)."),
         try params(SwiftWipePackageCommand.Options.self)]
    }

    public static func run(_ options: SwiftWipePackageCommand.Options, invocation: ParsedInvocation) async throws {
        try await SwiftWipePackageCommand.run(options, scope: .main)
    }
}

/// `sbm wipe extra`: only Tests/ and Benchmarks/ packages, each confirmed by its package.frame.
public enum SwiftWipeExtraCommand: BoundArgumentCommand {
    public static let name = "extra"

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Delete .build and .index-build of Tests/ and Benchmarks/ only (their package.frame must say tests/benchmarks); the main build stays (-r: every one below)."),
         try params(SwiftWipePackageCommand.Options.self)]
    }

    public static func run(_ options: SwiftWipePackageCommand.Options, invocation: ParsedInvocation) async throws {
        try await SwiftWipePackageCommand.run(options, scope: .extra)
    }
}

/// The options and execution `all`, `main` and `extra` share.
public enum SwiftWipePackageCommand {
    public struct Options: ArgumentGroup {
        @Arg(
            "root",
            help: "With -r: the directory to search (defaults to the project directory).",
            default: ""
        )
        public var root: String

        @Opt(
            "project",
            short: "p",
            help: "Project directory (defaults to CWD)."
        )
        public var project: String?

        @Flag(
            "recursive",
            short: "r",
            help: "Every package below the root, at any depth (limit with -d)."
        )
        public var recursive: Bool

        @Opt(
            "depth",
            short: "d",
            help: "With -r: how deep to search (root = 0)."
        )
        public var depth: Int?

        @Flag(
            "dry-run",
            short: "n",
            help: "List what would be deleted, with sizes and a total."
        )
        public var dryRun: Bool

        @Flag(
            "yes",
            short: "y",
            help: "Don't ask per cache (and don't size them first)."
        )
        public var yes: Bool

        @Flag(
            "ignore-keep",
            help: "Delete kept caches too, for this run."
        )
        public var ignoreKeep: Bool

        public init() {}
    }

    static func run(_ options: Options, scope: Wipe.Scope) async throws {
        if options.root == "help" {
            throw ArgumentValidationError("sbm wipe [all|main|extra|caches] [-r [root]] [-d N] [-n] [-y] [--ignore-keep]; details: sbm wipe <scope> --help")
        }
        guard options.recursive || (options.root.isEmpty && options.depth == nil) else {
            throw ArgumentValidationError("A root and --depth apply only with -r (sbm wipe --help).")
        }
        let project = try options.project.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileSystem.cwd()
        let root = options.root.isEmpty ? project : URL(fileURLWithPath: options.root, isDirectory: true)

        let plan = try Wipe.plan(
            .init(root: root, scope: scope, recursive: options.recursive, depth: options.depth,
                  ignoreKeep: options.ignoreKeep, measure: !options.yes),
            keep: options.ignoreKeep ? KeepList() : try KeepList.load()
        )
        try await execute(plan, dryRun: options.dryRun, interactive: !options.yes && !options.dryRun)
    }

    /// Runs a plan and reports per directory and in total. Also what `--wipe` on build, test
    /// and bench runs (not interactive: the flag is the answer).
    static func execute(_ plan: Wipe.Plan, dryRun: Bool, interactive: Bool) async throws {
        guard !plan.packages.isEmpty else {
            print("No packages under \(plan.root.path).")
            return
        }
        let before = try? FileSystem.default.volume(of: plan.root).available
        var deleted = 0, failed = 0, kept = 0, skipped = 0

        func label(_ item: Wipe.Item) -> String {
            let relative = item.directory.path.hasPrefix(plan.root.path + "/")
                ? String(item.directory.path.dropFirst(plan.root.path.count + 1))
                : item.directory.path
            return relative + (item.size.map { " (\($0.humanBytes))" } ?? "")
        }

        for item in plan.leftovers + plan.items {
            switch item.decision {
            case .kept(let entry, let reason):
                kept += 1
                print("→ kept \(label(item)) (keep: \(entry)\(reason.map { ", \($0)" } ?? ""))")
                continue
            case .running(let holder):
                skipped += 1
                print("→ skipped \(label(item)): build running (\(holder.executable), pid \(holder.pid))")
                continue
            case .delete:
                break
            }

            let leftover = Wipe.isLeftover(item.directory.lastPathComponent)
            if dryRun {
                print("would delete \(leftover ? "leftover " : "")\(label(item))")
                continue
            }
            if interactive, !leftover, !Terminal.confirm("Delete \(label(item))?", default: .no) {
                skipped += 1
                continue
            }
            do {
                try await Wipe.remove(item)
                deleted += 1
                print("✓ deleted \(label(item))")
            } catch {
                failed += 1
                print("✗ \(label(item)): \(error.localizedDescription)")
            }
        }

        if dryRun {
            print("\(plan.packages.count) packages; would free \(plan.measuredTotal.humanBytes) (\(plan.deletions.count) directories)")
            return
        }
        let freed = before.flatMap { before in
            (try? FileSystem.default.volume(of: plan.root).available).map { max(0, $0 - before) }
        }
        print("\(plan.packages.count) packages: \(deleted) deleted, \(kept) kept, \(skipped) skipped, \(failed) failed; freed ≈\((freed ?? 0).humanBytes)")
        if failed > 0 { throw WipeCommandError.failures(failed) }
    }
}

/// `sbm wipe caches -y`: SwiftPM's global cache (repository clones, artifacts, manifest cache),
/// through `swift package purge-cache`. Without `-y` it only shows the size.
public enum SwiftWipeCachesCommand: BoundArgumentCommand {
    public static let name = "caches"

    public struct Options: ArgumentGroup {
        @Flag(
            "yes",
            short: "y",
            help: "Purge. Without it, only the size is shown."
        )
        public var yes: Bool

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Purge SwiftPM's global cache (~/Library/Caches/org.swift.swiftpm; requires -y); every package then fetches its dependencies again."
            ),
            try params(
                Options.self
            ),
        ]
    }

    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
    }

    public static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let cache = directory
        guard FileSystem.default.exists(cache) else {
            print("\(cache.path) does not exist; nothing to purge.")
            return
        }
        let size = (try? FileSystem.default.size(of: cache))?.humanBytes ?? "unknown size"
        guard options.yes else {
            print("\(cache.path): \(size). Every package re-fetches its dependencies after a purge; run with -y to purge.")
            return
        }
        let result = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/xcrun"),
                arguments: ["swift", "package", "purge-cache"],
                workingDirectory: try FileSystem.cwd(),
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )
        guard case .exited(0) = result.exit else {
            throw WipeCommandError.purge_failed(String(decoding: result.stderr, as: UTF8.self))
        }
        print("Purged \(cache.path) (\(size)).")
    }
}

public enum WipeCommandError: Error, Sendable, LocalizedError {
    case failures(Int)
    case purge_failed(String)

    public var errorDescription: String? {
        switch self {
        case .failures(let count): return "\(count) cache directories could not be deleted."
        case .purge_failed(let output): return "swift package purge-cache failed: \(output)"
        }
    }
}
