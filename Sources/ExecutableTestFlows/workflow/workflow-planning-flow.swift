import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var workflowPlanningFlow: TestFlow {
        TestFlow("workflow-planning", tags: ["workflow", "pkl", "paths"]) {
            Step("copied stages/defaults/needs/publish config resolves into typed operations") {
                let fixture = try TypedWorkflowFixture()
                defer { fixture.remove() }
                let workspace = try WorkflowPlanning.discover(startingAt: fixture.root.appendingPathComponent("nested"))
                let plan = try await WorkflowPlanning.resolve("agentic_debug", in: workspace)
                try Expect.equal(plan.stages.map(\.id), ["agentic", "runtime", "ag_io", "media", "host"], "stages retain user-defined order")
                try Expect.equal(plan.stages[1].needs, ["agentic"], "explicit needs is preserved")
                try Expect.equal(plan.stages[0].operations.count, 4, "initial stage has guarded update, build, test and typed publish")
                try Expect.equal(plan.stages[0].operations[0].description, "update [when: never]", "first package does not update")
                try Expect.equal(plan.stages[1].operations[0].description, "update [when: dependency_stale]", "downstream update guard is typed")
                try Expect.true(plan.stages[1].operations[3].description.hasPrefix("publish [when: verified"), "publish is its own typed operation")
                try Expect.equal(plan.stages[4].operations.count, 3, "host does not run an undeclared test")
                try Expect.true(plan.requiresMessage, "runtime commit message is required")
                try Expect.true(plan.includesPublication, "typed publication is visible to planner")
                let suffix = try await WorkflowPlanning.resolve("agentic_debug", in: workspace, from: "ag_io")
                try Expect.equal(suffix.stages.map(\.id), ["ag_io", "media", "host"], "--from is a read-only planning suffix")
            }

            Step("stage dependency, guard, and path errors fail closed") {
                let fixture = try TypedWorkflowFixture()
                defer { fixture.remove() }
                let unknownNeed = fixture.original.replacingOccurrences(of: "needs { \"agentic\" }", with: "needs { \"unlisted\" }")
                try fixture.write(unknownNeed, to: ".sbm/workflows.pkl")
                do {
                    _ = try await WorkflowPlanning.resolve("agentic_debug", in: WorkflowPlanning.load(root: fixture.root))
                    try Expect.false(true, "unknown need must be rejected")
                } catch WorkflowConfigurationError.unknownDependency {
                    try Expect.true(true, "unknown need rejected")
                }
                let invalidGuard = fixture.original.replacingOccurrences(of: "dependency_stale", with: "arbitrary_code")
                try fixture.write(invalidGuard, to: ".sbm/workflows.pkl")
                do {
                    _ = try await WorkflowPlanning.resolve("agentic_debug", in: WorkflowPlanning.load(root: fixture.root))
                    try Expect.false(true, "unknown condition must be rejected")
                } catch WorkflowConfigurationError.invalidPolicy {
                    try Expect.true(true, "invalid condition rejected")
                }
                let traversal = fixture.original.replacingOccurrences(of: "runtime = \"AgenticRuntime\"", with: "runtime = \"../outside\"")
                try fixture.write(traversal, to: ".sbm/workflows.pkl")
                do {
                    _ = try await WorkflowPlanning.resolve("agentic_debug", in: WorkflowPlanning.load(root: fixture.root))
                    try Expect.false(true, "traversal must be rejected")
                } catch WorkflowConfigurationError.invalidPackagePath {
                    try Expect.true(true, "traversal rejected")
                }
            }
        }
    }

    static var workflowExecutionFlow: TestFlow {
        TestFlow("workflow-execution", tags: ["workflow", "execution", "git"]) {
            Step("typed operations run in dependency order with publish before next update") {
                let fixture = try TypedWorkflowFixture()
                defer { fixture.remove() }
                let plan = try await WorkflowPlanning.resolve("agentic_debug", in: WorkflowPlanning.load(root: fixture.root))
                let performer = WorkflowSpy()
                try await WorkflowExecution.execute(plan, message: "Publish verified changes", allowPublish: true, performer: performer)
                let events = await performer.events()
                let firstPublish = try XCTIndex(events, "publish:Agentic")
                let runtimeUpdate = try XCTIndex(events, "update:AgenticRuntime")
                try Expect.true(firstPublish < runtimeUpdate, "upstream publication precedes downstream SwiftPM update")
                try Expect.equal(events.filter { $0.hasPrefix("publish:") }.count, 5, "all five stages publish on green")
                try Expect.false(events.contains("update:Agentic"), "first stage's never update guard is honored")
                try Expect.equal(events.filter { $0.hasPrefix("test:") }.count, 4, "only the four declared test products run")
            }

            Step("failed tests and missing authorization never publish") {
                let fixture = try TypedWorkflowFixture()
                defer { fixture.remove() }
                let plan = try await WorkflowPlanning.resolve("agentic_debug", in: WorkflowPlanning.load(root: fixture.root))
                let unauthorized = WorkflowSpy()
                do {
                    try await WorkflowExecution.execute(plan, message: "Publish verified changes", allowPublish: false, performer: unauthorized)
                    try Expect.false(true, "publishing without consent must be rejected")
                } catch WorkflowConfigurationError.publishNotAuthorized {
                    try Expect.true(true, "publish authorization is mandatory")
                }
                try Expect.equal(await unauthorized.events(), [], "rejection happens before any operation")
                let noMessage = WorkflowSpy()
                do {
                    try await WorkflowExecution.execute(plan, message: nil, allowPublish: true, performer: noMessage)
                    try Expect.false(true, "required message must fail before execution")
                } catch WorkflowConfigurationError.missingMessage {
                    try Expect.true(true, "missing message rejected")
                }
                try Expect.equal(await noMessage.events(), [], "message validation is pre-execution")
                let failed = WorkflowSpy(failAt: "t_ar_main")
                do {
                    try await WorkflowExecution.execute(plan, message: "Publish verified changes", allowPublish: true, performer: failed)
                    try Expect.false(true, "test failure must propagate")
                } catch WorkflowSpy.Failure.test {
                    try Expect.true(true, "test failure stops execution")
                }
                let events = await failed.events()
                try Expect.true(events.contains("publish:Agentic"), "first stage was published")
                try Expect.false(events.contains("publish:AgenticRuntime"), "failing stage cannot publish")
                try Expect.false(events.contains("update:AgenticIO"), "next stage cannot start")
            }
        }
    }
}

private func XCTIndex(_ values: [String], _ prefix: String) throws -> Int {
    guard let index = values.firstIndex(where: { $0.hasPrefix(prefix) }) else { throw WorkflowSpy.Failure.missingEvent }
    return index
}

private actor WorkflowSpy: WorkflowOperationPerforming {
    enum Failure: Error { case test, missingEvent }
    private var log: [String] = []
    private let failAt: String?
    init(failAt: String? = nil) { self.failAt = failAt }
    func update(at directory: URL) async throws { log.append("update:\(directory.lastPathComponent)") }
    func build(at directory: URL, configuration: Build.Config.Mode) async throws { log.append("build:\(directory.lastPathComponent)") }
    func test(products: [String], at directory: URL) async throws {
        for product in products {
            log.append("test:\(directory.lastPathComponent):\(product)")
            if product == failAt { throw Failure.test }
        }
    }
    func publish(at directory: URL, branch: String, message: String, commit: Bool, push: Bool) async throws {
        log.append("publish:\(directory.lastPathComponent):\(branch):\(message)")
    }
    func events() -> [String] { log }
}

private struct TypedWorkflowFixture {
    let root: URL
    let original: String
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("workflow-typed-\(UUID().uuidString)", isDirectory: true)
        original = """
        packages {
            agentic = "Agentic"
            runtime = "AgenticRuntime"
            ag_io = "AgenticIO"
            media = "AgenticMedia"
            host = "AgenticHost"
        }
        workflows {
            agentic_debug {
                inputs { message = "required" }
                defaults {
                    branch = "master"
                    configuration = "debug"
                    onFailure = "stop"
                    update { when = "dependency_stale" }
                    publish { when = "verified" commit = true push = true message = "$message" }
                }
                stages = [
                    { id = "agentic" package = "agentic" test = "t_agentic" update { when = "never" } }
                    { id = "runtime" package = "runtime" needs { "agentic" } test = "t_ar_main" }
                    { id = "ag_io" package = "ag_io" needs { "runtime" } test = "t_aio_all" }
                    { id = "media" package = "media" needs { "ag_io" } test = "amtest" }
                    { id = "host" package = "host" needs { "media" } }
                ]
            }
        }
        """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(original, to: ".sbm/workflows.pkl")
        for (folder, product) in [("Agentic", "t_agentic"), ("AgenticRuntime", "t_ar_main"), ("AgenticIO", "t_aio_all"), ("AgenticMedia", "amtest")] {
            try write("// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"\(folder)\", products: [.executable(name: \"\(product)\", targets: [\"Tests\"])], targets: [.executableTarget(name: \"Tests\")])", to: "\(folder)/Package.swift")
            try write("print(\"fixture\")", to: "\(folder)/Sources/Tests/main.swift")
            try write("""
            uuid = "00000000-0000-0000-0000-000000000001"
            name = "\(folder)"
            types { "binary" }
            versions { release { major = 1 minor = 0 patch = 0 } }
            compile { use = false arguments {} }
            tests { primary = "\(product)" }
            details = ""
            author = ""
            update = ""
            """, to: "\(folder)/build-object.pkl")
        }
        try write("// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"AgenticHost\", targets: [])", to: "AgenticHost/Package.swift")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
    }
    func write(_ text: String, to relative: String) throws {
        let path = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: path, atomically: true, encoding: .utf8)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

