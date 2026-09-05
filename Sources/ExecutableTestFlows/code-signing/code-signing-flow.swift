import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var codeSigningFlow: TestFlow {
        TestFlow(
            "code-signing",
            tags: ["codesign", "security", "macos"]
        ) {
            Step("identity output is parsed into typed identities") {
                let identities = CodeSigning.parseIdentities(
                    """
                      1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Test Developer (ABCDE12345)"
                      2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: Test Developer (ABCDE12345)"
                         2 valid identities found
                    """
                )

                try Expect.equal(identities.count, 2, "two valid identities are parsed")
                try Expect.equal(
                    identities[0].kind,
                    CodeSigning.IdentityKind.appleDevelopment,
                    "Apple Development identity is classified"
                )
                try Expect.equal(
                    identities[1].kind,
                    CodeSigning.IdentityKind.developerIDApplication,
                    "Developer ID Application identity is classified"
                )
            }

            Step("portable signing identity selectors parse deterministically") {
                try Expect.equal(
                    try CodeSigning.IdentitySelector(
                        argument: "ad-hoc"
                    ),
                    .adHoc,
                    "ad-hoc selector parses"
                )
                try Expect.equal(
                    try CodeSigning.IdentitySelector(
                        argument: "apple-development"
                    ),
                    .kind(.appleDevelopment),
                    "Apple Development selector remains machine portable"
                )
                try Expect.equal(
                    try CodeSigning.IdentitySelector(
                        argument: "developer-id-application"
                    ),
                    .kind(.developerIDApplication),
                    "Developer ID selector parses"
                )
                try Expect.equal(
                    try CodeSigning.IdentitySelector(
                        argument: "0123456789ABCDEF0123456789ABCDEF01234567"
                    ),
                    .fingerprint(
                        "0123456789ABCDEF0123456789ABCDEF01234567"
                    ),
                    "explicit fingerprint remains available as an escape hatch"
                )
            }

            Step("installed signing identities can be discovered") {
                let identities = try await CodeSigning.identities()
                for identity in identities {
                    try Expect.true(!identity.fingerprint.isEmpty, "identity fingerprint is non-empty")
                    try Expect.true(!identity.name.isEmpty, "identity name is non-empty")
                }
            }

            Step("ad hoc signing can sign inspect and verify an executable") {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "executable-codesign-\(UUID().uuidString)",
                        isDirectory: true
                    )
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                defer { try? FileManager.default.removeItem(at: directory) }

                let target = directory.appendingPathComponent("fixture")
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: "/usr/bin/true"),
                    to: target
                )

                let result = try await CodeSigning.sign(
                    .init(
                        target: target,
                        signer: .adHoc,
                        identifier: "com.executable.codesign-fixture"
                    )
                )

                try Expect.true(result.verification.valid, "freshly signed executable verifies")
                try Expect.true(result.inspection.signed, "freshly signed executable is inspectable")
                try Expect.equal(
                    result.inspection.identifier,
                    Optional("com.executable.codesign-fixture"),
                    "requested signing identifier is retained"
                )
                try Expect.true(result.inspection.adHoc, "fixture uses the explicit ad hoc signer")
            }
        }
    }
}
