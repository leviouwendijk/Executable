import Executable
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

            Step("fixture resolves and runs its declared executable test product") {
                let fixture = try SwiftPackageFixture()
                defer { fixture.remove() }
                try sampleTestBuildObject().write(
                    to: fixture.root.appendingPathComponent("build-object.pkl"),
                    atomically: true,
                    encoding: .utf8
                )
                let plan = try await Tests.resolve(at: fixture.root)
                try Expect.equal(plan.products, ["fixture-cli"], "fixture test resolves declared product")
                try await Tests.execute(plan)
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
