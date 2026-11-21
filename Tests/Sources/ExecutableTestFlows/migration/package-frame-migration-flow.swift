import Executable
import ExecutableLegacy
import Foundation
import Interfaces
import TestFlows

extension ExecutableFlowSuite {
    static var packageFrameMigrationFlow: TestFlow {
        TestFlow("package-frame-migration", tags: ["migration", "frame", "pkl", "git"]) {
            Step("a pkl project becomes package.frame, Tests/package.frame and a pushed release tag") {
                let fixture = try await MigrationFixture(
                    compile: #"use = true arguments { "--targets" "FixtureCLI" }"#,
                    tests: #"tests { primary = "t_fixture" groups { smoke { "t_fixture" } } }"#,
                    testPackage: true
                )
                defer { fixture.remove() }

                let result = try await PackageFrameMigration.migrate(at: fixture.project)

                try Expect.equal(result.package.deployProducts, ["fixture-cli"], "--targets maps to the product that builds it")
                try Expect.equal(result.package.buildArguments, [], "nothing else to build with")
                guard case .package(let package) = try PackageFrame.read(result.packageFrame) else {
                    throw MigrationFixtureError("package.frame declares a package")
                }
                try Expect.equal(package, result.package, "package.frame holds the migrated package")

                guard let testsFrame = result.testsFrame, case .tests(let tests) = try PackageFrame.read(testsFrame) else {
                    throw MigrationFixtureError("Tests/package.frame declares the tests")
                }
                try Expect.equal(tests.primary, "t_fixture", "primary carries over")
                try Expect.equal(tests.groups["smoke"], ["t_fixture"], "groups carry over")
                try Expect.false(result.unsplitTests, "the tests already sit in Tests/")

                try Expect.equal(result.tag, .tagged(.init(major: 1, minor: 4, patch: 0)), "the pkl release version is tagged")
                try Expect.contains(try await fixture.remoteTags(), "1.4.0", "the tag is pushed")

                for name in ["build-object.pkl", "compiled.pkl"] {
                    try Expect.false(
                        FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(name).path),
                        "\(name) is removed"
                    )
                }
                let ignore = try String(contentsOf: fixture.project.appendingPathComponent(".gitignore"), encoding: .utf8)
                try Expect.true(result.gitignoreChanged, ".gitignore was updated")
                try Expect.false(ignore.contains("compiled.pkl"), "compiled.pkl rules are dropped")
                try Expect.true(ignore.split(separator: "\n").contains(".build/"), ".build is ignored at any depth")
                try Expect.false(ignore.split(separator: "\n").contains("/.build"), "the anchored rule is gone")

                do {
                    _ = try await PackageFrameMigration.migrate(at: fixture.project)
                    try Expect.false(true, "a migrated project is not migrated twice")
                } catch PackageFrameMigration.MigrationError.notLegacy {
                    try Expect.true(true, "no build-object.pkl left to migrate")
                }
            }

            Step("a dirty tree is migrated but not tagged; unsplit tests are reported") {
                let fixture = try await MigrationFixture(
                    compile: #"use = true arguments { "--products" "fixture-cli" "FixtureApp" }"#,
                    tests: #"tests { primary = "fixture-cli" }"#,
                    testPackage: false
                )
                defer { fixture.remove() }
                try "dirty".write(to: fixture.project.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

                let result = try await PackageFrameMigration.migrate(at: fixture.project)

                try Expect.equal(result.package.deployProducts, ["fixture-cli", "FixtureApp"], "--products carries over in order")
                guard case .skipped(let version, _) = result.tag else {
                    throw MigrationFixtureError("a dirty tree must not be tagged")
                }
                try Expect.equal(version, .init(major: 1, minor: 4, patch: 0), "the untagged version is reported")
                try Expect.equal(try await fixture.remoteTags(), [], "nothing is pushed")
                try Expect.true(result.unsplitTests, "tests without a Tests/ package are reported")
                guard let testsFrame = result.testsFrame, case .tests(let tests) = try PackageFrame.read(testsFrame) else {
                    throw MigrationFixtureError("Tests/package.frame keeps the declaration before the tests move")
                }
                try Expect.equal(tests.primary, "fixture-cli", "the declared primary survives the migration")
                let plan = try await Tests.resolve(at: fixture.project)
                try Expect.equal(plan.runs.map(\.package), [fixture.project], "unsplit tests run from the root package")
                try Expect.equal(plan.products, ["fixture-cli"], "the declared primary is what runs")
            }

            Step("discovery finds projects within depth under each root, never in hidden directories") {
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("modernize-discover-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let layout = [
                    "libs/Alpha",
                    "libs/Beta",
                    "api/swift/service/Gamma",
                    "api/swift/service/deep/Delta",
                    "libs/Alpha/.build/checkouts/Hidden",
                    "single",
                ]
                for path in layout {
                    let directory = root.appendingPathComponent(path, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try "name = \"x\"".write(to: directory.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8)
                }

                let libs = try PackageFrameMigration.discover(in: [root.appendingPathComponent("libs")], depth: 1)
                try Expect.equal(libs.map(\.lastPathComponent), ["Alpha", "Beta"], "direct children; .build is not entered")

                let api = try PackageFrameMigration.discover(in: [root.appendingPathComponent("api/swift")], depth: 2)
                try Expect.equal(api.map(\.lastPathComponent), ["Gamma"], "two levels down, not three")

                let both = try PackageFrameMigration.discover(
                    in: [root.appendingPathComponent("single"), root.appendingPathComponent("libs"), root.appendingPathComponent("libs")],
                    depth: 1
                )
                try Expect.equal(both.map(\.lastPathComponent), ["Alpha", "Beta", "single"], "a project root counts itself; duplicates collapse")
            }

            Step("local builds stay local and a project without compile deploys nothing") {
                let local = try await MigrationFixture(
                    compile: #"use = true arguments { "--debug" "--local" "--products" "fixture-cli" }"#,
                    tests: nil,
                    testPackage: false
                )
                defer { local.remove() }
                let localResult = try await PackageFrameMigration.migrate(at: local.project, tag: false)
                try Expect.isNil(localResult.package.deployProducts, "--local means nothing is deployed")
                try Expect.equal(
                    localResult.package.flaglessArguments,
                    ["--debug", "--products", "fixture-cli"],
                    "a flagless build still builds the same products locally"
                )

                let library = try await MigrationFixture(compile: #"use = false arguments { }"#, tests: nil, testPackage: false)
                defer { library.remove() }
                let libraryResult = try await PackageFrameMigration.migrate(at: library.project, tag: false)
                try Expect.equal(libraryResult.package, PackageConfiguration(), "an unused compile clause becomes an empty package")
            }
        }
    }
}

/// The Swift package fixture inside a git clone of a local bare repository, with a
/// build-object.pkl at release 1.4.0 and a compiled.pkl, all committed and pushed.
private struct MigrationFixture {
    let root: URL
    let remote: URL
    let project: URL
    private let package: SwiftPackageFixture

    init(compile: String, tests: String?, testPackage: Bool) async throws {
        package = try SwiftPackageFixture()
        root = package.root.deletingLastPathComponent()
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        remote = root.appendingPathComponent("remote.git", isDirectory: true)
        project = package.root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if testPackage {
            // A test package split out before the migration, not yet described by package.frame.
            try package.writeTestPackage()
            try FileManager.default.removeItem(at: project.appendingPathComponent("Tests/package.frame"))
        }
        try """
        uuid = "00000000-0000-0000-0000-000000000005"
        name = "ExecutableFixture"
        types { "binary" }
        versions { release { major = 1 minor = 4 patch = 0 } }
        compile { \(compile) }
        \(tests ?? "")
        details = ""
        author = ""
        update = ""
        """.write(to: project.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8)
        try "compiled { version { major = 1 minor = 3 patch = 0 } arguments { } }"
            .write(to: project.appendingPathComponent("compiled.pkl"), atomically: true, encoding: .utf8)
        try "/.build\n\n# auto-added ignorables:\ncompiled.pkl\n/compiled.pkl\n**/compiled.pkl\n"
            .write(to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        try await run(root, ["init", "--bare", "-b", "master", remote.path])
        try await run(project, ["init", "-b", "master"])
        try await run(project, ["config", "user.name", "Fixture"])
        try await run(project, ["config", "user.email", "fixture@example.invalid"])
        try await run(project, ["config", "tag.gpgSign", "false"])
        try await run(project, ["config", "commit.gpgSign", "false"])
        try await run(project, ["add", "-A"])
        try await run(project, ["commit", "-m", "fixture"])
        try await run(project, ["remote", "add", "origin", remote.path])
        try await run(project, ["push", "-u", "origin", "master"])
    }

    func remove() {
        package.remove()
        try? FileManager.default.removeItem(at: root)
    }

    func remoteTags() async throws -> [String] {
        try await run(root, ["--git-dir", remote.path, "tag", "--list"])
            .split(whereSeparator: \.isNewline).map(String.init)
    }

    @discardableResult
    private func run(_ directory: URL, _ arguments: [String]) async throws -> String {
        let result = try await GitRepo.git(directory, arguments)
        guard result.code == 0 else {
            throw MigrationFixtureError("git \(arguments.joined(separator: " ")) failed: \(result.err)")
        }
        return result.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MigrationFixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
