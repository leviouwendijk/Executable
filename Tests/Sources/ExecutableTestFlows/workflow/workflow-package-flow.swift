import Arguments
import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var workflowPackageFlow: TestFlow {
        TestFlow("workflow-package", tags: ["sbm", "package", "workflow", "safety"]) {
            Step("pkg and p resolve the same positional package/action command") {
                let spec = try SwiftBuildManagerCommand.spec()
                for arguments in [
                    ["pkg", "runtime", "update", "--verify"],
                    ["p", "runtime", "update", "-v"],
                    ["pkg", "runtime", "ship", "--stage-all", "-m", "Fix runtime"],
                ] {
                    let parsed = try Arguments.parse(arguments, spec: spec)
                    try Expect.equal(parsed.commandPath.map(\.rawValue), ["sbm", "pkg"], "canonical package command")
                    try Expect.equal(try parsed.require("reference", as: String.self), "runtime", "package reference")
                }
            }

            Step("update-only does not require test declarations; aliases are workspace-bound") {
                let fixture = try SinglePackageFixture(withTests: false)
                defer { fixture.remove() }
                let workspace = try WorkflowPlanning.load(root: fixture.root)
                let plan = try await WorkflowPackagePlanning.resolve("runtime", in: workspace, action: .update)
                try Expect.equal(plan.stages[0].directory, fixture.package, "package alias resolves inside workspace")
                try Expect.equal(plan.stages[0].operations.map(\.description), ["update [when: always]"], "update only")
                do {
                    _ = try WorkflowPlanning.packageDirectory("unknown", in: workspace)
                    try Expect.false(true, "unknown alias must fail")
                } catch WorkflowConfigurationError.missingPackage {
                    try Expect.true(true, "unknown package rejected")
                }
            }

            Step("verify, ship, and update -v plan correct typed operations") {
                let fixture = try SinglePackageFixture(withTests: true)
                defer { fixture.remove() }
                let workspace = try WorkflowPlanning.load(root: fixture.root)
                let verify = try await WorkflowPackagePlanning.resolve("runtime", in: workspace, action: .verify)
                try Expect.equal(verify.stages[0].operations.map(\.description), ["build [debug]", "test: fixture_tests"], "verify build and configured test")
                let updateVerify = try await WorkflowPackagePlanning.resolve("runtime", in: workspace, action: .update, verifyAfterUpdate: true)
                try Expect.equal(updateVerify.stages[0].operations.map(\.description), ["update [when: always]", "build [debug]", "test: fixture_tests"], "update followed by verification")
                let ship = try await WorkflowPackagePlanning.resolve("runtime", in: workspace, action: .ship)
                try Expect.true(ship.includesPublication, "ship publishes")
                try Expect.equal(ship.stages[0].operations.count, 3, "ship build, test, publish")
                let updateShip = try await WorkflowPackagePlanning.resolve("runtime", in: workspace, action: .update, shipAfterUpdate: true)
                try Expect.equal(updateShip.stages[0].operations.count, 4, "update-ship update, build, test, publish")
                try Expect.equal(updateShip.stages[0].needs, [], "single-package execution has no workflow prerequisites")
            }

            Step("ships never publish after a failing test and require authorization") {
                let fixture = try SinglePackageFixture(withTests: true)
                defer { fixture.remove() }
                let plan = try await WorkflowPackagePlanning.resolve("runtime", in: WorkflowPlanning.load(root: fixture.root), action: .ship)
                let unauthorized = PackageOperationSpy()
                do {
                    try await WorkflowExecution.execute(plan, message: "example", allowPublish: false, performer: unauthorized)
                    try Expect.false(true, "publish without authorization must fail")
                } catch WorkflowConfigurationError.publishNotAuthorized {
                    try Expect.true(true, "publication blocked")
                }
                try Expect.equal(await unauthorized.events(), [], "blocked before build")
                let failed = PackageOperationSpy(failTest: true)
                do {
                    try await WorkflowExecution.execute(plan, message: "example", allowPublish: true, performer: failed)
                    try Expect.false(true, "test failure must stop shipping")
                } catch PackageOperationSpy.TestFailure.failed {
                    try Expect.true(true, "test failure propagated")
                }
                try Expect.false((await failed.events()).contains("publish"), "failed tests never publish")
                let okay = PackageOperationSpy()
                try await WorkflowExecution.execute(plan, message: "example", allowPublish: true, performer: okay)
                try Expect.equal(await okay.events(), ["build", "test:fixture_tests", "publish"], "verified path uses existing executor")
            }

            Step("ship CLI requires explicit stage-all permission before any operations") {
                let exit = await SwiftBuildManagerCommand.run(arguments: ["pkg", "runtime", "ship", "-m", "message"])
                try Expect.true(exit != 0, "ship without --stage-all is rejected up front")
            }

            Step("package dry-run dispatch succeeds without mutating anything") {
                let fixture = try SinglePackageFixture(withTests: false)
                defer { fixture.remove() }
                let exit = await SwiftBuildManagerCommand.run(arguments: ["p", "runtime", "update", "-v", "--dry-run", "--workspace", fixture.root.path])
                // --verify demands local test configuration, unlike bare update.
                try Expect.true(exit != 0, "update --verify without declared tests fails at planning")
                let safe = await SwiftBuildManagerCommand.run(arguments: ["p", "runtime", "update", "--dry-run", "--workspace", fixture.root.path])
                try Expect.equal(safe, Int32(0), "update dry-run succeeds without SwiftPM mutation")
            }
        }
    }
}

private actor PackageOperationSpy: WorkflowOperationPerforming {
    enum TestFailure: Error { case failed }
    private var log: [String] = []
    private let failTest: Bool
    init(failTest: Bool = false) { self.failTest = failTest }
    func update(at directory: URL) async throws { log.append("update") }
    func build(at directory: URL, configuration: Build.Config.Mode) async throws { log.append("build") }
    func test(products: [String], at directory: URL) async throws {
        log.append("test:" + products.joined(separator: ","))
        if failTest { throw TestFailure.failed }
    }
    func publish(at directory: URL, branch: String, message: String, commit: Bool, push: Bool) async throws {
        log.append("publish")
    }
    func events() -> [String] { log }
}

private struct SinglePackageFixture {
    let root: URL
    let package: URL

    init(withTests: Bool) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sbm-pkg-\(UUID().uuidString)", isDirectory: true)
        package = root.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("Sources/FixtureTests"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".sbm"), withIntermediateDirectories: true)
        try """
        packages { runtime = "Runtime" }
        workflows { }
        """.write(to: root.appendingPathComponent(".sbm/workflows.pkl"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.2
        import PackageDescription
        let package = Package(name: "Runtime", products: [.executable(name: "fixture_tests", targets: ["FixtureTests"])], targets: [.executableTarget(name: "FixtureTests")])
        """.write(to: package.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "print(\"fixture\")\n".write(to: package.appendingPathComponent("Sources/FixtureTests/main.swift"), atomically: true, encoding: .utf8)
        if withTests {
            try """
            uuid = "00000000-0000-0000-0000-000000000003"
            name = "Runtime"
            types { "binary" }
            versions { release { major = 1 minor = 0 patch = 0 } }
            compile { use = false arguments { } }
            tests { primary = "fixture_tests" }
            details = ""
            author = ""
            update = ""
            """.write(to: package.appendingPathComponent("build-object.pkl"), atomically: true, encoding: .utf8)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
