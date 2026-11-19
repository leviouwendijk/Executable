import Foundation
import Testing
import Executable

extension ExecutableTestSuite {
    static let remoteBuildObjectSuite = TestSuite(
        "remote-build-object",
        title: "Remote build-object decoding (offline fixtures)",
        tags: ["executable", "pkl", "remote"]
    ) {
        Test("modern source decodes without network") {
            let original = BuildObjectConfiguration(
                uuid: UUID(),
                name: "remote-build",
                types: [.binary, .script],
                versions: .init(release: .init(major: 1, minor: 2, patch: 3)),
                compile: .init(use: true, arguments: ["-O"]),
                details: "remote fixture",
                author: "test",
                update: "manual"
            )
            let decoded = try BuildObjectConfiguration.parseCompatible(original.string())
            try Expect.equal(decoded.uuid, original.uuid)
            try Expect.equal(decoded.name, original.name)
            try Expect.equal(decoded.types, original.types)
            try Expect.equal(decoded.compile.arguments, original.compile.arguments)
        }

        Test("legacy source is modernized without network") {
            let legacy = """
                uuid = "2D45ED1F-3F26-4C11-93D1-BB92E9C1A734"
                name = "legacy-remote"
                type = "binary"
                version { major = 2 minor = 1 patch = 4 }
                details = "legacy"
                author = "test"
                update = "manual"
                """
            let decoded = try BuildObjectConfiguration.parseCompatible(legacy)
            try Expect.equal(decoded.name, "legacy-remote")
            try Expect.equal(decoded.types, [.binary])
            try Expect.equal(decoded.versions.release.patch, 4)
        }

        Test("invalid source is rejected") {
            _ = try Expect.throwsError(PklParserError.self) {
                _ = try BuildObjectConfiguration.parseCompatible("not a Pkl document")
            }
        }
    }
}
