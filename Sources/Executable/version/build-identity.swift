import Foundation
import Interfaces
import Readers
import Version

/// What a deployed binary was built from, written beside it in `<product>.metadata` after a
/// successful deploy. It replaces compiled.pkl: a failed build, or a machine that did not
/// update, never looks current, because only a deploy writes it.
public struct BuildIdentity: Sendable, Equatable {
    /// The newest release tag reachable from the built commit; nil before the first release.
    public let version: ObjectVersion?
    public let commit: String
    public let dirty: Bool

    public init(version: ObjectVersion?, commit: String, dirty: Bool) {
        self.version = version
        self.commit = commit
        self.dirty = dirty
    }

    /// The identity of HEAD; nil outside a git repository.
    public static func current(at directory: URL) async -> BuildIdentity? {
        guard let commit = try? await GitRepo.gitOut(directory, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !commit.isEmpty
        else { return nil }
        return .init(
            version: (try? await ReleaseTags.latest(at: directory)) ?? nil,
            commit: commit,
            dirty: (try? await GitRepo.isDirty(directory)) ?? true
        )
    }

    var metadataLines: [String] {
        [
            "Version=\(version.map(ReleaseTags.name(for:)) ?? "")",
            "Commit=\(commit)",
            "Dirty=\(dirty)",
        ]
    }
}

/// A deployed product's `<product>.metadata`.
public struct DeployedMetadata: Sendable, Equatable {
    public let values: [String: String]

    public var version: ObjectVersion? { values["Version"].flatMap(ReleaseTags.version(of:)) }
    public var commit: String? { values["Commit"].flatMap { $0.isEmpty ? nil : $0 } }
    public var dirty: Bool { values["Dirty"] == "true" }

    public init(values: [String: String]) {
        self.values = values
    }

    public init(parsing text: String) {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        self.init(values: values)
    }

    /// The metadata of a product deployed to `root`, or nil when it was never deployed there.
    public static func read(product: String, in root: URL) throws -> DeployedMetadata? {
        let file = root.appendingPathComponent("\(product).metadata")
        let result = try TextFileReader(file).read(options: .init(missingFilePolicy: .returnEmpty))
        return result.existed ? .init(parsing: result.text) : nil
    }
}
