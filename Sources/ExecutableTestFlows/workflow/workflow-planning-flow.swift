import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var workflowPlanningFlow: TestFlow {
        TestFlow("workflow-planning", tags: ["workflow", "pkl", "paths"]) {
            Step("workspace discovery, aliases, action order and from filtering") {
                let sandbox = try WorkflowPlanningFixture()
                defer { sandbox.remove() }
                let workspace = try WorkflowPlanning.discover(startingAt: sandbox.root.appendingPathComponent("nested"))
                try Expect.equal(workspace.root, sandbox.root.resolvingSymlinksInPath().standardizedFileURL, "nearest workspace owns its configuration")
                let plan = try await WorkflowPlanning.resolve("pipeline", in: workspace)
                try Expect.equal(plan.steps.map(\.package), ["one", "two"], "step order preserved")
                try Expect.equal(plan.steps[0].actions.map(\.description), ["build", "commit [not executed]", "push [not executed]"], "action sequence preserved")
                let continuation = try await WorkflowPlanning.resolve("pipeline", in: workspace, from: "two")
                try Expect.equal(continuation.steps.map(\.package), ["two"], "from selects suffix")
            }

            Step("test action uses local tests declaration and resolves executable product") {
                let sandbox = try WorkflowPlanningFixture()
                defer { sandbox.remove() }
                let workspace = try WorkflowPlanning.load(root: sandbox.root)
                let plan = try await WorkflowPlanning.resolve("test_only", in: workspace)
                try Expect.equal(plan.steps[0].actions.map(\.description), ["test: fixture-cli"], "test product selected through existing resolver")
            }

            Step("parent traversal and symlink escape are rejected") {
                let sandbox = try WorkflowPlanningFixture()
                defer { sandbox.remove() }
                let malicious = """
                packages { one = "../outside" }
                workflows { pipeline { steps = [ { package = "one" actions { "build" } } ] } }
                """
                try sandbox.write(malicious, to: ".sbm/workflows.pkl")
                let workspace = try WorkflowPlanning.load(root: sandbox.root)
                do {
                    _ = try await WorkflowPlanning.resolve("pipeline", in: workspace)
                    try Expect.false(true, "traversal must not resolve")
                } catch WorkflowConfigurationError.invalidPackagePath {
                    try Expect.true(true, "traversal rejected")
                }
                try sandbox.write(sandbox.original, to: ".sbm/workflows.pkl")
                let outside = FileManager.default.temporaryDirectory.appendingPathComponent("workflow-outside-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: outside) }
                try FileManager.default.createSymbolicLink(at: sandbox.root.appendingPathComponent("escaped"), withDestinationURL: outside)
                let escaped = sandbox.original.replacingOccurrences(of: "one = \"one\"", with: "one = \"escaped\"")
                try sandbox.write(escaped, to: ".sbm/workflows.pkl")
                let linked = try WorkflowPlanning.load(root: sandbox.root)
                do {
                    _ = try await WorkflowPlanning.resolve("pipeline", in: linked)
                    try Expect.false(true, "symlink escape must not resolve")
                } catch WorkflowConfigurationError.invalidPackagePath {
                    try Expect.true(true, "symlink escape rejected")
                }
            }

            Step("invalid action, unknown workflow and unknown package fail closed") {
                let sandbox = try WorkflowPlanningFixture()
                defer { sandbox.remove() }
                let workspace = try WorkflowPlanning.load(root: sandbox.root)
                do {
                    _ = try await WorkflowPlanning.resolve("missing", in: workspace)
                    try Expect.false(true, "unknown workflow must fail")
                } catch WorkflowConfigurationError.unknownWorkflow {
                    try Expect.true(true, "unknown workflow rejected")
                }
                let invalidAction = sandbox.original.replacingOccurrences(of: "\"commit\"", with: "\"shell:rm -rf /\"")
                try sandbox.write(invalidAction, to: ".sbm/workflows.pkl")
                let invalid = try WorkflowPlanning.load(root: sandbox.root)
                do {
                    _ = try await WorkflowPlanning.resolve("pipeline", in: invalid)
                    try Expect.false(true, "unsupported action must fail")
                } catch WorkflowConfigurationError.unsupportedAction {
                    try Expect.true(true, "unsupported action rejected")
                }
            }
        }
    }
}

private struct WorkflowPlanningFixture {
    let root: URL
    let original: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("workflow-planning-\(UUID().uuidString)", isDirectory: true)
        original = """
        packages {
            one = "one"
            two = "two"
        }
        workflows {
            pipeline {
                steps = [
                    { package = "one" actions { "build" "commit" "push" } }
                    { package = "two" actions { "update" "build" } }
                ]
            }
            test_only {
                steps = [ { package = "one" actions { "test" } } ]
            }
        }
        """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(original, to: ".sbm/workflows.pkl")
        try write("// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"One\", products: [.executable(name: \"fixture-cli\", targets: [\"App\"])], targets: [.executableTarget(name: \"App\")])", to: "one/Package.swift")
        try write("// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"Two\", targets: [])", to: "two/Package.swift")
        try write("print(\"fixture\")", to: "one/Sources/App/main.swift")
        try write("""
        uuid = "00000000-0000-0000-0000-000000000001"
        name = "One"
        types { "binary" }
        versions { release { major = 1 minor = 0 patch = 0 } }
        compile { use = false arguments { } }
        tests { primary = "fixture-cli" }
        details = ""
        author = ""
        update = ""
        """, to: "one/build-object.pkl")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
    }

    func write(_ text: String, to relative: String) throws {
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
