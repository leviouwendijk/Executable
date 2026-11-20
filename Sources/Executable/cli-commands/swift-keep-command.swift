import Arguments
import Foundation
import IO
import Readers
import Roots

/// `sbm keep`: the packages whose caches `sbm wipe` leaves alone (`.config/sbm/keep.frame`).
public enum SwiftKeepCommand: ArgumentCommand {
    public static let name = "keep"
    public static let defaultChild = SwiftKeepListCommand.self

    public static let children: [ArgumentCommandType] = [
        SwiftKeepListCommand.self,
        SwiftKeepCheckCommand.self,
        SwiftKeepAddCommand.self,
        SwiftKeepRemoveCommand.self,
    ]

    public static func components() throws -> [CommandComponentLowerable] {
        [
            about(
                "Packages whose .build/.index-build sbm wipe leaves alone (.config/sbm/keep.frame in every root)."
            ),
        ]
    }

    static func path(_ raw: String) throws -> URL {
        raw.isEmpty ? try FileSystem.cwd() : URL(fileURLWithPath: raw, isDirectory: true)
    }

    /// `/Users/levi/x` → `~/x`, so the entry reads the same for everyone sharing a root.
    static func homeRelative(_ path: String) -> String {
        let home = Roots.home.standardizedFileURL.path
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

public enum SwiftKeepListCommand: RunnableArgumentCommand {
    public static let name = "list"

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Every keep entry, with the file it comes from.")]
    }

    public static func run(_ invocation: ParsedInvocation) async throws {
        let list = try KeepList.load()
        guard !list.entries.isEmpty else {
            print("No keep entries (\(KeepList.privateFile().path)).")
            return
        }
        for entry in list.entries {
            let caches = entry.caches.count == KeepEntry.Cache.allCases.count
                ? "" : " [\(entry.caches.sorted().map(\.rawValue).joined(separator: ", "))]"
            print("\(entry.name)\(caches): \(entry.packages.joined(separator: ", "))")
            if let reason = entry.reason { print("    \(reason)") }
            if let file = entry.file { print("    \(SwiftKeepCommand.homeRelative(file.path))") }
        }
    }
}

public enum SwiftKeepCheckCommand: BoundArgumentCommand {
    public static let name = "check"

    public struct Options: ArgumentGroup {
        @Arg("dir", help: "Package directory (defaults to CWD).", default: "")
        public var directory: String

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Whether a package's caches are kept, and by which entry."), try params(Options.self)]
    }

    public static func run(_ options: Options, invocation: ParsedInvocation) async throws {
        let package = try SwiftKeepCommand.path(options.directory)
        let list = try KeepList.load()
        for cache in KeepEntry.Cache.allCases {
            if let entry = list.keeping(package, cache: cache) {
                print("\(cache.directoryName): kept by '\(entry.name)'\(entry.reason.map { " (\($0))" } ?? "")")
            } else {
                print("\(cache.directoryName): not kept")
            }
        }
    }
}

public enum SwiftKeepAddCommand: BoundArgumentCommand {
    public static let name = "add"

    public struct Options: ArgumentGroup {
        @Arg("path", help: "A package directory or a pattern (*, **); defaults to CWD.", default: "")
        public var path: String

        @Opts("caches", take: .many, help: "build and/or index (default both).")
        public var caches: [String]

        @Opt("reason", help: "Why; shown by sbm keep and in wipe runs.")
        public var reason: String?

        @Opt("name", help: "Binding name (defaults to the package's directory name).")
        public var name: String?

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Add a keep entry to the private root's keep.frame."), try params(Options.self)]
    }

    public static func run(_ options: Options, invocation: ParsedInvocation) async throws {
        let raw = options.path.isEmpty ? try FileSystem.cwd().path : options.path
        let absolute = raw.hasPrefix("/") || raw.hasPrefix("~")
            ? raw : try FileSystem.cwd().appendingPathComponent(raw).standardizedFileURL.path
        let pattern = SwiftKeepCommand.homeRelative(absolute)

        let caches = try options.caches
            .flatMap { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
            .map { value -> KeepEntry.Cache in
                guard let cache = KeepEntry.Cache(rawValue: value) else {
                    throw ArgumentValidationError("--caches takes build and/or index, not '\(value)'.")
                }
                return cache
            }

        let name = options.name ?? KeepList.defaultName(for: pattern)
        let existing = try KeepList.load()
        if let taken = existing.entries.first(where: { $0.name == name }) {
            throw KeepError.name_taken(name, taken.file)
        }

        let entry = KeepEntry(
            name: name,
            packages: [pattern],
            caches: caches.isEmpty ? Set(KeepEntry.Cache.allCases) : Set(caches),
            reason: options.reason
        )
        let file = KeepList.privateFile()
        let source = FileSystem.default.exists(file) ? try TextFileReader(file).read().text : nil
        let updated = KeepList.adding(entry, to: source)
        _ = try KeepList.parse(updated, file: file)
        try KeepList.write(updated, to: file)
        print("Added '\(name)' (\(pattern)) to \(SwiftKeepCommand.homeRelative(file.path))")
    }
}

public enum SwiftKeepRemoveCommand: BoundArgumentCommand {
    public static let name = "rm"

    public struct Options: ArgumentGroup {
        @Arg("entry", help: "An entry name, or a package directory one entry names exactly (defaults to CWD).", default: "")
        public var entry: String

        public init() {}
    }

    public static func components() throws -> [CommandComponentLowerable] {
        [about("Remove a keep entry from the file that declares it."), try params(Options.self)]
    }

    public static func run(_ options: Options, invocation: ParsedInvocation) async throws {
        let list = try KeepList.load()
        let target: KeepEntry
        if let named = list.entries.first(where: { $0.name == options.entry }) {
            target = named
        } else {
            let directory = try SwiftKeepCommand.path(options.entry)
            let pattern = SwiftKeepCommand.homeRelative(directory.standardizedFileURL.path)
            guard let exact = list.entries.first(where: { $0.packages == [pattern] || $0.packages == [directory.path] }) else {
                throw KeepError.no_match(options.entry.isEmpty ? directory.path : options.entry)
            }
            target = exact
        }
        guard let file = target.file else { throw KeepError.unknown_name(target.name) }
        let updated = try KeepList.removing(target.name, from: TextFileReader(file).read().text)
        try KeepList.write(updated, to: file)
        print("Removed '\(target.name)' from \(SwiftKeepCommand.homeRelative(file.path))")
    }
}
