import Executable
import ExecutableLegacy
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var testDeclarationFlow: TestFlow {
        TestFlow("test-declaration", tags: ["pkl", "tests", "products"]) {
            Step("tests Pkl section round-trips with stable group rendering") {
                let text = sampleTestBuildObject()
                let parsed = try BuildObjectConfiguration.parse(text)
                try Expect.equal(parsed.tests?.primary, "fixture-cli", "primary test product decodes")
                try Expect.equal(parsed.tests?.groups["smoke"], ["fixture-cli"], "test group decodes")
                let rendered = parsed.string()
                try Expect.true(rendered.contains("tests {"), "rendered build-object contains tests section")
                let again = try BuildObjectConfiguration.parse(rendered)
                try Expect.equal(again.tests, parsed.tests, "test declaration round-trips")
            }

            Step("primary group all and product selection are deterministic") {
                let config = TestConfiguration(primary: "one", groups: [
                    "smoke": ["one", "two", "two"], "full": ["two", "three"]
                ])
                let available: Set<String> = ["one", "two", "three"]
                try Expect.equal(try config.selectedProducts(for: .primary, availableProducts: available), ["one"], "default selects primary")
                try Expect.equal(try config.selectedProducts(for: .group("smoke"), availableProducts: available), ["one", "two"], "group selection preserves order and deduplicates")
                try Expect.equal(try config.selectedProducts(for: .all, availableProducts: available), ["one", "two", "three"], "all selection is stable and deduplicated")
                try Expect.equal(try config.selectedProducts(for: .product("three"), availableProducts: available), ["three"], "individual declared product resolves")
            }

            Step("undeclared and missing products fail during resolution") {
                let config = TestConfiguration(primary: "one", groups: ["quick": ["two"]])
                do {
                    _ = try config.selectedProducts(for: .primary, availableProducts: ["one"])
                    try Expect.false(true, "missing group product must fail")
                } catch TestConfiguration.ValidationError.unavailableProducts(let products) {
                    try Expect.equal(products, ["two"], "missing product error identifies unavailable declaration")
                }
                do {
                    _ = try config.selectedProducts(for: .group("unknown"), availableProducts: ["one", "two"])
                    try Expect.false(true, "unknown group must fail")
                } catch TestConfiguration.ValidationError.unknownGroup(let name) {
                    try Expect.equal(name, "unknown", "unknown group error identifies group")
                }
            }

            Step("a test package counts every product and never runs interactive ones in all") {
                let config = TestConfiguration(groups: ["live": ["t_live"]], interactive: ["t_shell"])
                let available: Set<String> = ["t_main", "t_live", "t_shell"]
                try Expect.equal(
                    try config.selectedProducts(for: .all, availableProducts: available, testPackage: true),
                    ["t_live", "t_main"], "all runs declared and undeclared products, minus interactive ones"
                )
                try Expect.equal(
                    try config.selectedProducts(for: .product("t_main"), availableProducts: available, testPackage: true),
                    ["t_main"], "an undeclared product of a test package can be run by name"
                )
                try Expect.throwsError("several non-interactive products leave no implicit primary") {
                    _ = try config.selectedProducts(for: .primary, availableProducts: available, testPackage: true)
                }
                let single = TestConfiguration(interactive: ["t_shell"])
                try Expect.equal(
                    try single.selectedProducts(for: .primary, availableProducts: ["t_main", "t_shell"], testPackage: true),
                    ["t_main"], "the only non-interactive product is the primary"
                )
                try Expect.throwsError("an interactive primary is refused") {
                    _ = try TestConfiguration(primary: "t_shell", interactive: ["t_shell"])
                        .selectedProducts(for: .primary, availableProducts: ["t_shell"], testPackage: true)
                }
            }

            Step("tests declared only in a legacy build-object.pkl point at sbm modernize") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try sampleTestBuildObject().write(
                    to: fixture.root.appendingPathComponent("build-object.pkl"),
                    atomically: true,
                    encoding: .utf8
                )
                do {
                    _ = try await Tests.resolve(at: fixture.root)
                    try Expect.false(true, "legacy tests { } must not be run by core")
                } catch ConfigurationFileError.legacy {
                    try Expect.true(true, "legacy tests point at sbm modernize")
                }
            }

            Step("Tests/package.frame before the tests move runs declared products from the root") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                let tests = fixture.root.appendingPathComponent("Tests", isDirectory: true)
                try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
                try "import Executable;\n\nlet tests: Tests = .{ .primary = \"fixture-cli\", .groups = .{ .apps = [\"FixtureApp\"] } };\n"
                    .write(to: tests.appendingPathComponent("package.frame"), atomically: true, encoding: .utf8)

                let plan = try await Tests.resolve(at: fixture.root)
                try Expect.equal(plan.runs.map(\.package), [fixture.root], "products run in the root package")
                try Expect.equal(plan.products, ["fixture-cli"], "the declared primary runs")
                let all = try await Tests.resolve(at: fixture.root, selection: .all)
                try Expect.equal(all.products, ["fixture-cli", "FixtureApp"], "only declared products count among the root's executables")
                let inside = try await Tests.resolve(at: tests)
                try Expect.equal(inside.runs.map(\.package), [fixture.root], "from inside Tests/ the root package still runs them")
                try await Tests.execute(plan)
            }

            Step("nested test package runs its only product without a tests declaration") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try "import Executable;\n\nlet package: Package = .{};\n".write(
                    to: fixture.root.appendingPathComponent("package.frame"),
                    atomically: true,
                    encoding: .utf8
                )
                try fixture.writeTestPackage()
                let plan = try await Tests.resolve(at: fixture.root)
                try Expect.equal(plan.runs.map(\.package.lastPathComponent), ["Tests"], "products run in the nested test package")
                try Expect.equal(plan.products, ["t_fixture"], "the only test product is the primary")
                try await Tests.execute(plan)

                let inside = try await Tests.resolve(at: fixture.root.appendingPathComponent("Tests"))
                try Expect.equal(inside.products, ["t_fixture"], "resolving from inside the test package finds the same product")
            }

            Step("benchmarks are their own package kind: sbm bench finds them in release, sbm test never") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try "import Executable;\n\nlet package: Package = .{};\n".write(
                    to: fixture.root.appendingPathComponent("package.frame"),
                    atomically: true,
                    encoding: .utf8
                )
                try fixture.writeTestPackage()
                try fixture.writeBenchmarkPackage()

                let tests = try await Tests.resolve(at: fixture.root, selection: .all)
                try Expect.equal(tests.runs.map(\.package.lastPathComponent), ["Tests"], "tests never include the benchmark package")
                try Expect.equal(tests.runs.map(\.mode), [.debug], "tests run in debug")

                let benchmarks = try await Tests.resolve(at: fixture.root, kind: .benchmarks)
                try Expect.equal(benchmarks.runs.map(\.package.lastPathComponent), ["Benchmarks"], "benchmarks resolve to Benchmarks/")
                try Expect.equal(benchmarks.products, ["b_fixture"], "the only benchmark product is the primary")
                try Expect.equal(benchmarks.runs.map(\.mode), [.release], "benchmarks run in release")
                try await Tests.execute(benchmarks)

                let inside = try await Tests.resolve(at: fixture.root.appendingPathComponent("Benchmarks"), kind: .benchmarks)
                try Expect.equal(inside.products, ["b_fixture"], "resolving from inside Benchmarks/ finds the same product")
            }

            Step("test package reaching its parent through another dependency is refused") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try "import Executable;\n\nlet package: Package = .{};\n".write(
                    to: fixture.root.appendingPathComponent("package.frame"),
                    atomically: true,
                    encoding: .utf8
                )
                try fixture.writeTestPackage(throughSibling: true)
                do {
                    _ = try await Tests.resolve(at: fixture.root)
                    try Expect.false(true, "a second route to the parent must fail")
                } catch Tests.RunError.parentReachedThroughDependencies(_, let dependents) {
                    try Expect.equal(dependents, ["middle"], "the error names the dependency that reaches the parent")
                }
            }
        }
    }
}

private func sampleTestBuildObject() -> String {
    """
    uuid = "00000000-0000-0000-0000-000000000001"
    name = "ExecutableFixture"
    types { "binary" }
    versions {
        release {
            major = 1
            minor = 0
            patch = 0
        }
    }
    compile {
        use = false
        arguments { }
    }
    tests {
        primary = "fixture-cli"
        groups {
            smoke { "fixture-cli" }
        }
    }
    details = ""
    author = ""
    update = ""
    """
}
