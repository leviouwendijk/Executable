import Executable
import Foundation
import Path
import Version

/// Moves a build-object.pkl project to package.frame:
///
/// - `compile { }` becomes `.build` and `.deploy` in `package.frame`;
/// - `tests { }` becomes `Tests/package.frame` when the project has a `Tests/` package;
/// - the release version becomes a git tag on HEAD, unless a release tag already exists;
/// - build-object.pkl and compiled.pkl are removed, and .gitignore drops the compiled.pkl
///   rules and ignores `.build/` at any depth.
///
/// Moving test targets into `Tests/` is not part of it; `unsplitTests` reports when the
/// project still declares tests but has no test package.
public enum PackageFrameMigration {
    public enum TagOutcome: Sendable, Equatable {
        case existing(ObjectVersion)
        case tagged(ObjectVersion)
        case skipped(ObjectVersion, reason: String)
    }

    public struct Result: Sendable {
        public let package: PackageConfiguration
        public let packageFrame: URL
        public let testsFrame: URL?
        public let unsplitTests: Bool
        public let tag: TagOutcome
        public let removed: [URL]
        public let gitignoreChanged: Bool
    }

    public enum MigrationError: Error, Sendable, LocalizedError {
        case notLegacy(URL)
        case alreadyMigrated(URL)
        case unknownTarget(String)
        case danglingFlag(String)

        public var errorDescription: String? {
            switch self {
            case .notLegacy(let directory): return "No build-object.pkl in \(directory.path)."
            case .alreadyMigrated(let file): return "\(file.path) already exists; remove build-object.pkl by hand if it is stale."
            case .unknownTarget(let target): return "compile { } names target '\(target)', which no executable product builds."
            case .danglingFlag(let flag): return "compile { } ends with '\(flag)' without a value."
            }
        }
    }

    public static func migrate(
        at directory: URL,
        tag: Bool = true
    ) async throws -> Result {
        let project = directory.standardizedFileURL
        guard let legacyURL = try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: project) else {
            throw MigrationError.notLegacy(project)
        }
        let packageFrame = project.appendingPathComponent(PackageFrame.fileName)
        if try BuildObjectDiscovery.local(named: PackageFrame.fileName, in: project) != nil {
            throw MigrationError.alreadyMigrated(packageFrame)
        }

        let legacy = try PklFile.read(from: legacyURL) { try BuildObjectConfiguration.parseCompatible($0) }
        let package = try await packageConfiguration(from: legacy.compile, in: project)

        // Tag before writing anything, while HEAD is the commit the version describes.
        let tagOutcome = tag
            ? try await tagRelease(legacy.versions.release, at: project)
            : .skipped(legacy.versions.release, reason: "tagging disabled")

        try write(PackageFrame.source(package), to: packageFrame, in: project)

        var testsFrame: URL?
        var unsplitTests = false
        if let tests = legacy.tests {
            let testsDirectory = project.appendingPathComponent(Tests.conventionalDirectory, isDirectory: true)
            if try BuildObjectDiscovery.local(named: "Package.swift", in: testsDirectory) != nil {
                let file = testsDirectory.appendingPathComponent(PackageFrame.fileName)
                if try BuildObjectDiscovery.local(named: PackageFrame.fileName, in: testsDirectory) == nil {
                    try write(PackageFrame.source(tests), to: file, in: testsDirectory)
                    testsFrame = file
                }
            } else {
                unsplitTests = true
            }
        }

        var removed: [URL] = []
        for name in [BuildObjectDiscovery.legacyConfiguration, BuildObjectDiscovery.legacyCompiled, "build-object.pkl.bak"] {
            if let file = try BuildObjectDiscovery.local(named: name, in: project) {
                try FileManager.default.removeItem(at: file)
                removed.append(file)
            }
        }

        return Result(
            package: package,
            packageFrame: packageFrame,
            testsFrame: testsFrame,
            unsplitTests: unsplitTests,
            tag: tagOutcome,
            removed: removed,
            gitignoreChanged: try updateGitignore(in: project)
        )
    }

    /// Projects to migrate under each root: the root itself when it holds a build-object.pkl,
    /// and every directory within `depth` levels below it that does. Hidden directories
    /// (`.build`, `.git`) are not entered.
    public static func discover(in roots: [URL], depth: Int) throws -> [URL] {
        var projects: [URL] = []
        for root in roots.map(\.standardizedFileURL) {
            if try BuildObjectDiscovery.local(named: BuildObjectDiscovery.legacyConfiguration, in: root) != nil {
                projects.append(root)
            }
            let entries = try PathWalker(
                root: root,
                configuration: .init(maxDepth: depth + 1, emitDirectories: false)
            ).walk()
            projects += entries
                .filter { $0.url.lastPathComponent == BuildObjectDiscovery.legacyConfiguration }
                .map { $0.url.deletingLastPathComponent().standardizedFileURL }
        }
        var seen = Set<String>()
        return projects
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
    }

    /// `compile { use arguments }` as `.build` and `.deploy`. `--products` and `--targets`
    /// name what is deployed (targets mapped to the executable products that build them);
    /// `-l`/`--no-move` keep the build local, so nothing is deployed; other flags stay
    /// build arguments. A compile clause without products deploys every executable product.
    static func packageConfiguration(
        from compile: CompileInstructionDefaults,
        in project: URL
    ) async throws -> PackageConfiguration {
        guard compile.use else { return PackageConfiguration() }

        var arguments = compile.arguments
        if let first = arguments.first?.lowercased(), first == "build" || first == "sbm" {
            arguments.removeFirst()
        }

        var products: [String] = []
        var targets: [String] = []
        var rest: [String] = []
        var local = false
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--products", "--targets":
                var values: [String] = []
                index += 1
                while index < arguments.endIndex, !arguments[index].hasPrefix("-") {
                    values += arguments[index].split(separator: ",").map(String.init)
                    index += 1
                }
                guard !values.isEmpty else { throw MigrationError.danglingFlag(argument) }
                if argument == "--products" { products += values } else { targets += values }
                continue
            case "-l", "--local", "--no-move":
                local = true
            default:
                rest.append(argument)
            }
            index += 1
        }

        if !targets.isEmpty || products.isEmpty {
            let executables = try await Products.executables(in: project)
            for target in targets {
                guard let product = executables.first(where: { $0.targets.contains(target) || $0.name == target }) else {
                    throw MigrationError.unknownTarget(target)
                }
                products.append(product.name)
            }
            if products.isEmpty {
                products = executables.map(\.name)
            }
        }
        products = products.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }

        if local {
            return PackageConfiguration(buildArguments: rest + ["--products"] + products)
        }
        return PackageConfiguration(buildArguments: rest, deployProducts: products)
    }

    static func tagRelease(_ version: ObjectVersion, at project: URL) async throws -> TagOutcome {
        if let latest = try await ReleaseTags.latest(at: project) {
            return .existing(latest)
        }
        do {
            try await ReleaseTags.create(version, at: project)
            return .tagged(version)
        } catch {
            // Dirty, unpushed, already released, or no upstream: migrate anyway, tag by hand later.
            return .skipped(version, reason: error.localizedDescription)
        }
    }

    /// Drops the compiled.pkl rules and their heading, and unanchors `/.build`.
    static func updateGitignore(in project: URL) throws -> Bool {
        guard let file = try BuildObjectDiscovery.local(named: ".gitignore", in: project) else { return false }
        let original = try String(contentsOf: file, encoding: .utf8)
        let dropped: Set<String> = ["compiled.pkl", "/compiled.pkl", "**/compiled.pkl", "# auto-added ignorables:"]
        var lines = original.components(separatedBy: "\n")
            .filter { !dropped.contains($0.trimmingCharacters(in: .whitespaces)) }
            .map { $0.trimmingCharacters(in: .whitespaces) == "/.build" ? ".build/" : $0 }
        while lines.count > 1, lines[lines.count - 1].isEmpty, lines[lines.count - 2].isEmpty {
            lines.removeLast()
        }
        let updated = lines.joined(separator: "\n")
        guard updated != original else { return false }
        try updated.write(to: file, atomically: true, encoding: .utf8)
        return true
    }

    private static func write(_ source: String, to file: URL, in directory: URL) throws {
        try BuildObjectDiscovery.requireOwned(file, by: directory)
        try source.write(to: file, atomically: true, encoding: .utf8)
    }
}
