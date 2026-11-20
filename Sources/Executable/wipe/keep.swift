import Foundation
import Frame
import IO
import Path
import Readers
import Roots
import Writers

/// Packages whose build caches `sbm wipe` leaves alone: the `Keep` bindings of
/// `.config/sbm/keep.frame` in every root, private first.
///
///     import Executable;
///
///     let io: Keep = .{ .packages = ["~/main/programming/libraries/swiftlibs/IO"] };
///
///     let swiftbins: Keep = .{
///         .packages = ["~/main/programming/binaries/swiftbins/*"],
///         .caches = ["build"],
///         .reason = "slow full rebuilds; the index can go",
///     };
///
/// Keeping a cache is a choice about this machine, not a property of the package, so it lives
/// here and never in package.frame.
public struct KeepEntry: Sendable, Equatable {
    public enum Cache: String, Sendable, Codable, CaseIterable, Comparable {
        case build
        case index

        /// The directory the cache lives in, beside Package.swift.
        public var directoryName: String {
            switch self {
            case .build: return ".build"
            case .index: return ".index-build"
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    public let name: String
    /// Absolute or `~` paths, each a directory or a pattern (`*`, `**`, `?`, `[…]`).
    public let packages: [String]
    public let caches: Set<Cache>
    public let reason: String?
    public let file: URL?

    public init(
        name: String,
        packages: [String],
        caches: Set<Cache> = Set(Cache.allCases),
        reason: String? = nil,
        file: URL? = nil
    ) {
        self.name = name
        self.packages = packages
        self.caches = caches
        self.reason = reason
        self.file = file
    }

    /// Whether `package` (a directory holding Package.swift) is one of this entry's packages.
    /// Both sides are compared resolved through symlinks.
    public func matches(_ package: URL, home: URL = Roots.home) -> Bool {
        let components = FileSystem.default.resolve(package).pathComponents.filter { $0 != "/" }
        return packages.contains { pattern in
            KeepEntry.pattern(pattern, home: home).matches(components)
        }
    }

    /// The pattern with `~` expanded and its literal prefix resolved through symlinks.
    static func pattern(_ raw: String, home: URL) -> PathPattern {
        let expanded = SbmSettings.expand(raw, home: home).path
        let parts = expanded.split(separator: "/").map(String.init)
        let literal = parts.prefix { PathPatternComponent.interpreting($0).isConcrete }
        let prefix = FileSystem.default.resolve(URL(fileURLWithPath: "/" + literal.joined(separator: "/"), isDirectory: true))
        let resolved = prefix.pathComponents.filter { $0 != "/" } + parts.dropFirst(literal.count)
        return PathPattern(interpreting: resolved)
    }
}

public struct KeepList: Sendable, Equatable {
    public static let location = SbmSettings.location
    public static let fileName = "keep.frame"

    public let entries: [KeepEntry]

    public init(entries: [KeepEntry] = []) {
        self.entries = entries
    }

    /// The entry keeping `cache` of `package`, if any.
    public func keeping(_ package: URL, cache: KeepEntry.Cache) -> KeepEntry? {
        entries.first { $0.caches.contains(cache) && $0.matches(package) }
    }

    /// Every root's keep.frame, private first. A name used twice is an error naming both files.
    public static func load(roots: RootSet = Roots.load()) throws -> KeepList {
        var entries: [KeepEntry] = []
        for (_, directory) in roots.existing(location) {
            let file = directory.appendingPathComponent(fileName)
            guard FileSystem.default.exists(file) else { continue }
            for entry in try parse(TextFileReader(file).read().text, file: file) {
                if let other = entries.first(where: { $0.name == entry.name }) {
                    throw KeepError.duplicate_name(entry.name, other.file, file)
                }
                entries.append(entry)
            }
        }
        return .init(entries: entries)
    }

    public static func parse(_ source: String, file: URL? = nil) throws -> [KeepEntry] {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        return try document.bindings
            .filter { $0.type?.components.last == "Keep" }
            .map { binding in
                let fields = try document.decode(Fields.self, binding: binding.name)
                guard !fields.packages.isEmpty else { throw KeepError.no_packages(binding.name) }
                for pattern in fields.packages where !(pattern.hasPrefix("/") || pattern == "~" || pattern.hasPrefix("~/")) {
                    throw KeepError.relative_path(binding.name, pattern)
                }
                return KeepEntry(
                    name: binding.name,
                    packages: fields.packages,
                    caches: Set(fields.caches ?? KeepEntry.Cache.allCases),
                    reason: fields.reason,
                    file: file
                )
            }
    }

    /// Where `sbm keep add` writes: the private root's keep.frame.
    public static func privateFile(roots: RootSet = Roots.load()) -> URL {
        roots.privateRoot.url(location).appendingPathComponent(fileName)
    }

    // MARK: - Editing by source span; every other line stays as written.

    static let header = """
        import Executable;

        // Packages whose build caches `sbm wipe` leaves alone.

        """

    /// `source` (nil for a new file) with one binding appended.
    public static func adding(_ entry: KeepEntry, to source: String?) -> String {
        var fields = [".packages = [\(entry.packages.map(quoted).joined(separator: ", "))]"]
        if entry.caches != Set(KeepEntry.Cache.allCases) {
            fields.append(".caches = [\(entry.caches.sorted().map { quoted($0.rawValue) }.joined(separator: ", "))]")
        }
        if let reason = entry.reason {
            fields.append(".reason = \(quoted(reason))")
        }
        let binding = "let \(entry.name): Keep = .{ \(fields.joined(separator: ", ")) };\n"

        var text = source ?? header
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.hasSuffix("\n\n") { text += "\n" }
        return text + binding
    }

    /// `source` without the binding named `name`, and without the line it leaves empty.
    public static func removing(_ name: String, from source: String) throws -> String {
        let document = try Frame.parse(source, environment: ExecutableFrame.environment)
        guard let binding = document.binding(named: name) else { throw KeepError.unknown_name(name) }

        var start = source.index(source.startIndex, offsetBy: binding.range.start.offset)
        var end = source.index(source.startIndex, offsetBy: binding.range.end.offset)

        while end < source.endIndex, source[end] == " " || source[end] == "\t" { end = source.index(after: end) }
        if end < source.endIndex, source[end] == ";" { end = source.index(after: end) }
        while end < source.endIndex, source[end] == " " || source[end] == "\t" { end = source.index(after: end) }

        let lineStart = source[..<start].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        let ownsLine = source[lineStart..<start].allSatisfy { $0 == " " || $0 == "\t" }
        if ownsLine, end == source.endIndex || source[end] == "\n" {
            start = lineStart
            if end < source.endIndex { end = source.index(after: end) }
        }

        var result = String(source[..<start]) + String(source[end...])
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result
    }

    /// A binding name from a path: its last literal component, lowercased, as an identifier.
    public static func defaultName(for path: String) -> String {
        let literal = path.split(separator: "/").map(String.init)
            .last { PathPatternComponent.interpreting($0).isConcrete && $0 != "~" } ?? "keep"
        var name = literal.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.map(String.init).joined()
        if name.first?.isNumber ?? true { name = "_" + name }
        return name
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func write(_ source: String, to file: URL) throws {
        try FileWriter(file).write(source, options: .overwriteWithoutBackup)
    }
}

extension KeepList {
    struct Fields: Codable, Sendable, FrameDescribable {
        let packages: [String]
        let caches: [KeepEntry.Cache]?
        let reason: String?

        static var frameSchema: Frame.Schema {
            .object([
                .init("packages", .array(.string), required: true,
                      summary: "Package directories or patterns (*, **, ?, [...]), absolute or under ~."),
                .init("caches", .array(.string),
                      summary: "Which caches to keep: \"build\" (.build), \"index\" (.index-build); both by default."),
                .init("reason", .string, summary: "Why; shown by `sbm keep` and in dry runs."),
            ], summary: "Packages whose build caches `sbm wipe` leaves alone: a binding of .config/sbm/keep.frame.")
        }
    }
}

public enum KeepError: Error, Sendable, LocalizedError, Equatable {
    case duplicate_name(String, URL?, URL)
    case no_packages(String)
    case relative_path(String, String)
    case unknown_name(String)
    case name_taken(String, URL?)
    case no_match(String)

    public var errorDescription: String? {
        switch self {
        case .duplicate_name(let name, let first, let second):
            return "keep entry '\(name)' is declared in \(first?.path ?? "?") and \(second.path); names are unique across roots."
        case .no_packages(let name):
            return "keep entry '\(name)' has no .packages."
        case .relative_path(let name, let pattern):
            return "keep entry '\(name)': '\(pattern)' must be absolute or start with ~/."
        case .unknown_name(let name):
            return "No keep entry named '\(name)'."
        case .name_taken(let name, let file):
            return "A keep entry named '\(name)' already exists in \(file?.path ?? "a root"); choose another with --name."
        case .no_match(let what):
            return "No keep entry named or matching '\(what)'."
        }
    }
}
