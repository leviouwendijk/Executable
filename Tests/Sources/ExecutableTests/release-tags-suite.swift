import Executable
import Foundation
import Interfaces
import Testing
import Version

extension ExecutableTestSuite {
    static let releaseTagsSuite = TestSuite(
        "release-tags",
        title: "Release versions from git tags and deploy metadata",
        tags: ["executable", "version", "git"]
    ) {
        Test("release tags are bare or v-prefixed semver, nothing else") {
            try Expect.equal(ReleaseTag.version(of: "1.2.3"), .init(major: 1, minor: 2, patch: 3), "bare tag")
            try Expect.equal(ReleaseTag.version(of: "v1.2.3"), .init(major: 1, minor: 2, patch: 3), "v-prefixed tag is read")
            for tag in ["1.2", "1.2.3.4", "1.2.x", "release-1.2.3", "1..3", "", "v"] {
                try Expect.isNil(ReleaseTag.version(of: tag), "'\(tag)' is not a release tag")
            }
            try Expect.equal(ReleaseTag.name(for: .init(major: 0, minor: 4, patch: 1)), "0.4.1", "written tags are bare")
        }

        Test("increment tags HEAD with the next bare version and pushes it") {
            let fixture = try await TagFixture()
            defer { fixture.remove() }
            try Expect.isNil(try await GitRepo.latestRelease(at: fixture.work), "no release before the first tag")

            let first = try await GitRepo.release(.next(.minor), at: fixture.work)
            try Expect.isNil(first.from, "first release starts from nothing")
            try Expect.equal(first.to, .init(major: 0, minor: 1, patch: 0), "minor from nothing is 0.1.0")
            try Expect.contains(try await fixture.remoteTags(), "0.1.0", "the tag is pushed")

            try await fixture.commit("second")
            try await fixture.git(["tag", "-a", "v0.3.0", "-m", "v0.3.0"])
            try Expect.equal(try await GitRepo.latestRelease(at: fixture.work), .init(major: 0, minor: 3, patch: 0), "v-prefixed tags count as releases")

            try await fixture.commit("third")
            let next = try await GitRepo.release(.next(.patch), at: fixture.work)
            try Expect.equal(next.to, .init(major: 0, minor: 3, patch: 1), "the next release follows the newest tag")
        }

        Test("increment refuses dirty, unpushed and already-released HEADs") {
            let fixture = try await TagFixture()
            defer { fixture.remove() }

            try "changed".write(to: fixture.work.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            try await Expect.throwsError("uncommitted changes") {
                _ = try await GitRepo.release(.next(.patch), at: fixture.work)
            }
            try await fixture.git(["checkout", "--", "file.txt"])

            try await fixture.commit("local only", push: false)
            try await Expect.throwsError("commits not on the remote") {
                _ = try await GitRepo.release(.next(.patch), at: fixture.work)
            }
            try await fixture.git(["push"])

            _ = try await GitRepo.release(.next(.patch), at: fixture.work)
            try await Expect.throwsError("HEAD already carries a release") {
                _ = try await GitRepo.release(.next(.patch), at: fixture.work)
            }
        }

        Test("create tags an exact version, never one at or below the latest release") {
            let fixture = try await TagFixture()
            defer { fixture.remove() }
            try await GitRepo.release(.exact(.init(major: 2, minor: 0, patch: 1)), at: fixture.work)
            try Expect.contains(try await fixture.remoteTags(), "2.0.1", "the exact version is tagged and pushed")

            try await fixture.commit("next")
            try await Expect.throwsError("an older version is refused") {
                try await GitRepo.release(.exact(.init(major: 1, minor: 9, patch: 0)), at: fixture.work)
            }
            try await Expect.throwsError("the same version is refused") {
                try await GitRepo.release(.exact(.init(major: 2, minor: 0, patch: 1)), at: fixture.work)
            }
            try await GitRepo.release(.exact(.init(major: 2, minor: 1, patch: 0)), at: fixture.work)
            try Expect.equal(try await GitRepo.latestRelease(at: fixture.work), .init(major: 2, minor: 1, patch: 0), "a newer version is tagged")
        }

        Test("deployed products are behind until a deploy records the released version") {
            let fixture = try await TagFixture()
            defer { fixture.remove() }
            let deployRoot = fixture.root.appendingPathComponent("sbm-bin", isDirectory: true)
            try FileManager.default.createDirectory(at: deployRoot, withIntermediateDirectories: true)
            let package = PackageConfiguration(deployProducts: ["tool"])

            let untagged = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(untagged.behind, ["tool"], "a product never deployed is behind")

            _ = try await GitRepo.release(.next(.minor), at: fixture.work)
            let head = try await fixture.git(["rev-parse", "HEAD"])
            try "ProjectRootPath=/x\nVersion=0.0.9\nCommit=\(head)\nDirty=false\n"
                .write(to: deployRoot.appendingPathComponent("tool.metadata"), atomically: true, encoding: .utf8)
            let old = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(old.release, .init(major: 0, minor: 1, patch: 0), "release is the newest tag")
            try Expect.equal(old.behind, ["tool"], "a deploy below the release is behind")

            try "ProjectRootPath=/x\nVersion=0.1.0\nCommit=\(head)\nDirty=false\n"
                .write(to: deployRoot.appendingPathComponent("tool.metadata"), atomically: true, encoding: .utf8)
            let current = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(current.behind, [], "a deploy of the release is current")

            try "ProjectRootPath=/x\nBuildType=release\n"
                .write(to: deployRoot.appendingPathComponent("tool.metadata"), atomically: true, encoding: .utf8)
            let legacy = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(legacy.behind, ["tool"], "metadata written before build identities counts as behind")

            let library = try await PackageVersionStatus.inspect(at: fixture.work, configuration: PackageConfiguration(), deployedTo: deployRoot)
            try Expect.equal(library.behind, [], "nothing to deploy is never behind")
        }

        Test("a commit with a release tags it and pushes branch and tag together; a stale version commits nothing") {
            let fixture = try await TagFixture()
            defer { fixture.remove() }

            try "released".write(to: fixture.work.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            _ = try await GitManagerAction.commit(message: "released", push: false, release: .next(.minor), at: fixture.work)
            try Expect.contains(try await fixture.remoteTags(), "0.1.0", "the tag reaches the remote")
            try Expect.equal(
                try await fixture.git(["rev-parse", "origin/master"]),
                try await fixture.git(["rev-parse", "HEAD"]),
                "the branch is pushed with it, although push was false"
            )

            let before = try await fixture.git(["rev-parse", "HEAD"])
            try "stale".write(to: fixture.work.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            try await Expect.throwsError("a version not newer than the latest release") {
                _ = try await GitManagerAction.commit(message: "stale", push: true, release: .exact(.init(major: 0, minor: 0, patch: 1)), at: fixture.work)
            }
            try Expect.equal(try await fixture.git(["rev-parse", "HEAD"]), before, "nothing was committed")
        }

        Test("local products are the --products of a package without .deploy") {
            try Expect.equal(PackageConfiguration(buildArguments: ["--products", "app"]).localProducts, ["app"], "one product")
            try Expect.equal(PackageConfiguration(buildArguments: ["--products", "a", "b", "--no-move"]).localProducts, ["a", "b"], "values until the next flag")
            try Expect.equal(PackageConfiguration(buildArguments: ["--products", "a,b"]).localProducts, ["a", "b"], "comma-separated values")
            try Expect.equal(PackageConfiguration(buildArguments: ["--products", "app"], deployProducts: ["app"]).localProducts, [], "deployed products are not local")
            try Expect.equal(PackageConfiguration(buildArguments: ["--skip-products", "x"]).localProducts, [], "other flags name no local products")
        }

        Test("local products are behind until a build records HEAD, and again after a pull") {
            let fixture = try await TagFixture()
            defer { fixture.remove() }
            let deployRoot = fixture.root.appendingPathComponent("sbm-bin", isDirectory: true)
            let package = PackageConfiguration(buildArguments: ["--products", "app"])

            let never = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(never.behind, ["app"], "a product never built is behind")

            try BuildRecord.write(products: ["app"], project: fixture.work, mode: .release, identity: await BuildIdentity.current(at: fixture.work))
            let current = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(current.behind, [], "a build of HEAD is current, without any release")
            try Expect.equal(current.built.first?.metadata?.commit, try await fixture.git(["rev-parse", "HEAD"]), "the record holds the built commit")

            try await fixture.commit("pulled")
            let pulled = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(pulled.behind, ["app"], "a new commit makes the product behind, no tag needed")

            try FileManager.default.removeItem(at: fixture.work.appendingPathComponent(".build"))
            let wiped = try await PackageVersionStatus.inspect(at: fixture.work, configuration: package, deployedTo: deployRoot)
            try Expect.equal(wiped.behind, ["app"], "wiping .build removes the record with the binary")
        }
    }
}

/// A working clone of a local bare repository, with one pushed commit.
private struct TagFixture {
    let root: URL
    let remote: URL
    let work: URL

    init() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-tags-\(UUID().uuidString)", isDirectory: true)
        remote = root.appendingPathComponent("remote.git", isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await run(root, ["init", "--bare", "-b", "master", remote.path])
        try await run(root, ["clone", remote.path, work.path])
        try await git(["config", "user.name", "Fixture"])
        try await git(["config", "user.email", "fixture@example.invalid"])
        try await git(["config", "tag.gpgSign", "false"])
        try await git(["config", "commit.gpgSign", "false"])
        try await commit("first")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func commit(_ message: String, push: Bool = true) async throws {
        try message.write(to: work.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "file.txt"])
        try await git(["commit", "-m", message])
        if push { try await git(["push", "-u", "origin", "master"]) }
    }

    func remoteTags() async throws -> [String] {
        try await run(root, ["--git-dir", remote.path, "tag", "--list"])
            .split(whereSeparator: \.isNewline).map(String.init)
    }

    @discardableResult
    func git(_ arguments: [String]) async throws -> String {
        try await run(work, arguments)
    }

    @discardableResult
    private func run(_ directory: URL, _ arguments: [String]) async throws -> String {
        let result = try await GitRepo.git(directory, arguments)
        guard result.code == 0 else {
            throw TagFixtureError(arguments: arguments, message: result.err)
        }
        return result.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TagFixtureError: Error, CustomStringConvertible {
    let arguments: [String]
    let message: String
    var description: String { "git \(arguments.joined(separator: " ")) failed: \(message)" }
}
