import Foundation
import Interfaces
import Version

/// Released versions of package.frame projects are git tags: bare semver (`1.2.3`).
/// `v1.2.3` is read as well, never written.
public enum ReleaseTags {
    public enum TagError: Error, Sendable, LocalizedError {
        case dirty(URL)
        case unpushed(URL, ahead: Int)
        case exists(String)
        case alreadyReleased(String)
        case notNewer(String, latest: String)

        public var errorDescription: String? {
            switch self {
            case .dirty(let directory):
                return "\(directory.path) has uncommitted changes; commit them before tagging a release."
            case .unpushed(let directory, let ahead):
                return "\(directory.path) is \(ahead) commit(s) ahead of its upstream; push before tagging a release."
            case .exists(let tag):
                return "Tag \(tag) already exists (as \(tag) or v\(tag))."
            case .notNewer(let tag, let latest):
                return "\(tag) is not newer than the latest release \(latest)."
            case .alreadyReleased(let tag):
                return "HEAD is already released as \(tag); commit something new before the next release."
            }
        }
    }

    /// The version a tag names, or nil when it is not a release tag.
    public static func version(of tag: String) -> ObjectVersion? {
        let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        return .init(major: major, minor: minor, patch: patch)
    }

    /// The tag written for a version.
    public static func name(for version: ObjectVersion) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    /// The newest release tag reachable from HEAD.
    public static func latest(at directory: URL) async throws -> ObjectVersion? {
        try await tags(at: directory, ["tag", "--merged", "HEAD", "--list"])
            .compactMap(version(of:))
            .max()
    }

    /// Tags HEAD with the next version and pushes the tag to the upstream remote.
    @discardableResult
    public static func increment(
        _ level: ObjectVersionLevel,
        at directory: URL,
        push: Bool = true
    ) async throws -> (from: ObjectVersion?, to: ObjectVersion) {
        let from = try await latest(at: directory)
        var to = from ?? .zero()
        to.increment(level)
        try await create(to, at: directory, push: push)
        return (from, to)
    }

    /// Tags HEAD with `version` and pushes the tag to the upstream remote. Refuses a dirty or
    /// unpushed HEAD, a HEAD that is already released, a version tagged before, and a version
    /// not newer than the latest release.
    public static func create(
        _ version: ObjectVersion,
        at directory: URL,
        push: Bool = true
    ) async throws {
        guard try await !GitRepo.isDirty(directory) else { throw TagError.dirty(directory) }
        let divergence = try await GitRepo.divergence(directory)
        guard divergence.ahead == 0 else { throw TagError.unpushed(directory, ahead: divergence.ahead) }

        if let released = try await tags(at: directory, ["tag", "--points-at", "HEAD"]).first(where: { self.version(of: $0) != nil }) {
            throw TagError.alreadyReleased(released)
        }

        let tag = name(for: version)
        if let newest = try await latest(at: directory), version <= newest {
            throw TagError.notNewer(tag, latest: name(for: newest))
        }
        let existing = Set(try await tags(at: directory, ["tag", "--list"]))
        guard !existing.contains(tag), !existing.contains("v" + tag) else { throw TagError.exists(tag) }

        _ = try await GitRepo.gitOut(directory, ["tag", "-a", tag, "-m", tag])
        if push {
            let (remote, _) = try await GitRepo.upstream(directory)
            _ = try await GitRepo.gitOut(directory, ["push", remote, tag])
        }
    }

    private static func tags(at directory: URL, _ arguments: [String]) async throws -> [String] {
        try await GitRepo.gitOut(directory, arguments)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
