import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var pklRenderingFlow: TestFlow {
        TestFlow("pkl-rendering", tags: ["pkl", "roundtrip", "formatting"]) {
            Step("zero to two arguments stay inline") {
                for values in [[], ["--debug"], ["--products", "sbm"]] {
                    let instruction = CompileInstructionDefaults(use: true, arguments: values)
                    let text = instruction.contents()
                    try Expect.true(text.contains("arguments { "), "zero-to-two item collection remains inline")
                    try Expect.false(text.contains("arguments {\n"), "zero-to-two item collection does not introduce a newline")
                }
            }

            Step("three or more arguments render one per line and round-trip") {
                let values = ["--debug", "--products", "sbm", "quoted \"name\""]
                let instruction = CompileInstructionDefaults(use: true, arguments: values)
                let text = instruction.contents()
                try Expect.true(text.contains("arguments {\n"), "three-or-more item collection is multiline")
                try Expect.true(text.contains("        \"--debug\"\n"), "multiline items use an additional indentation level")
                let compiled = CompiledLocalBuildObject(
                    version: .init(major: 1, minor: 2, patch: 3),
                    arguments: values
                )
                let decoded = try CompiledLocalBuildObject.parse(compiled.string())
                try Expect.equal(decoded.arguments, values, "compiled arguments round-trip exactly")
                try Expect.equal(decoded.version, compiled.version, "compiled version round-trips exactly")
            }
        }
    }
}
