import Foundation
import Testing
import Executable

extension ExecutableTestSuite {
    static let pklRegressionSuite = TestSuite(
        "pkl",
        title: "Build-object Pkl compatibility",
        tags: ["version", "pkl"]
    ) {
        Test("modern configuration round trip") {
            let uuid = try fixture_uuid()
            let config = BuildObjectConfiguration(
                uuid: uuid,
                name: "demo",
                types: [.binary, .script],
                versions: .init(release: .init(major: 1, minor: 2, patch: 3)),
                compile: .init(use: true, arguments: ["-c", "debug"]),
                details: "a test", author: "author", update: "manual"
            )
            let decoded = try BuildObjectConfiguration.parse(config.string())
            try Expect.equal(decoded.name, "demo")
            try Expect.equal(decoded.uuid, uuid)
            try Expect.equal(Set(decoded.types.map(\.rawValue)), Set(["binary", "script"]))
            try Expect.equal(decoded.versions.release.patch, 3)
            try Expect.equal(decoded.compile.use, true)
            try Expect.equal(decoded.compile.arguments, ["-c", "debug"])
        }

        Test("legacy configuration parsing and modernization") {
            let source = """
                // legacy build-object
                uuid = "2D45ED1F-3F26-4C11-93D1-BB92E9C1A734"
                name = "old"
                type = "binary"
                version { major = 2 minor = 0 patch = 5 }
                details = "legacy"
                author = "author"
                update = "manual"
                """
            let decoded = try BuildObjectConfiguration.LegacyObject.parse(source)
            try Expect.equal(decoded.name, "old")
            try Expect.equal(decoded.version.patch, 5)
            try Expect.equal(decoded.modernize().types, [.binary])
        }

        Test("compiled configuration round trip") {
            let compiled = CompiledLocalBuildObject(
                version: .init(major: 4, minor: 3, patch: 2),
                arguments: ["-O", "-g"]
            )
            let decoded = try CompiledLocalBuildObject.parse(compiled.string())
            try Expect.equal(decoded.version.major, 4)
            try Expect.equal(decoded.arguments, ["-O", "-g"])
        }

        Test("compile defaults when omitted") {
            let decoded = try BuildObjectConfiguration.parse(basic_pkl)
            try Expect.equal(decoded.compile.use, false)
            try Expect.equal(decoded.compile.arguments, [])
        }

        Test("legacy numeric use and empty list") {
            let decoded = try BuildObjectConfiguration.parse(
                basic_pkl + "\ncompile { use = 2 arguments {} }"
            )
            try Expect.equal(decoded.compile.use, true)
            try Expect.equal(decoded.compile.arguments, [])
        }

        Test("last duplicate field wins") {
            let decoded = try BuildObjectConfiguration.parse(
                basic_pkl + "\nname = \"override\""
            )
            try Expect.equal(decoded.name, "override")
        }

        Test("missing required UUID is rejected") {
            let source = basic_pkl.replacingOccurrences(
                of: "uuid = \"2D45ED1F-3F26-4C11-93D1-BB92E9C1A734\"", with: ""
            )
            let error = try Expect.throwsError(PklParserError.self) {
                _ = try BuildObjectConfiguration.parse(source)
            }
            guard case .missingField("uuid") = error else {
                throw UnexpectedPklError(error)
            }
        }

        Test("invalid UUID is rejected") {
            let source = basic_pkl.replacingOccurrences(
                of: "2D45ED1F-3F26-4C11-93D1-BB92E9C1A734", with: "bad"
            )
            let error = try Expect.throwsError(PklParserError.self) {
                _ = try BuildObjectConfiguration.parse(source)
            }
            guard case .invalidValue(field: "uuid", value: _) = error else {
                throw UnexpectedPklError(error)
            }
        }

        Test("invalid type is rejected") {
            let source = basic_pkl.replacingOccurrences(
                of: "types { \"binary\" }", with: "types { 3 }"
            )
            _ = try Expect.throwsError(PklParserError.self) {
                _ = try BuildObjectConfiguration.parse(source)
            }
        }

        Test("missing release is rejected") {
            let source = basic_pkl.replacingOccurrences(
                of: "release { major = 0 minor = 1 patch = 0 }", with: ""
            )
            _ = try Expect.throwsError(PklParserError.self) {
                _ = try BuildObjectConfiguration.parse(source)
            }
        }

        Test("malformed syntax is rejected") {
            // Unlike the old test's unterminated string fixture, this is an
            // unequivocally incomplete assignment, so it exercises the lexer/parser.
            let error = try Expect.throwsError(PklParserError.self) {
                _ = try BuildObjectConfiguration.parse("name =")
            }
            guard case .syntaxError = error else {
                throw UnexpectedPklError(error)
            }
        }

        Test("render Pkl escaped scalar fields") {
            let fixture = BuildObjectConfiguration(
                uuid: try fixture_uuid(),
                name: "a\"b",
                types: [.binary],
                versions: .init(release: .init(major: 1, minor: 0, patch: 0)),
                compile: .init(use: false, arguments: ["slash\\path", "say \"yes\""]),
                details: "line one\nline two",
                author: "o'neal",
                update: "x\ty"
            )
            let parsed = try BuildObjectConfiguration.parse(fixture.string())
            try Expect.equal(parsed.name, fixture.name)
            try Expect.equal(parsed.details, fixture.details)
            try Expect.equal(parsed.compile.arguments, fixture.compile.arguments)
            try Expect.equal(parsed.update, fixture.update)
        }
    }
}

private struct UnexpectedPklError: Error {
    let underlying: PklParserError
    init(_ underlying: PklParserError) { self.underlying = underlying }
}

private func fixture_uuid() throws -> UUID {
    guard let uuid = UUID(uuidString: "2D45ED1F-3F26-4C11-93D1-BB92E9C1A734") else {
        throw FixtureError.invalidUUID
    }
    return uuid
}

private enum FixtureError: Error { case invalidUUID }

private let basic_pkl = """
    uuid = "2D45ED1F-3F26-4C11-93D1-BB92E9C1A734"
    name = "basic"
    types { "binary" }
    versions { release { major = 0 minor = 1 patch = 0 } }
    details = ""
    author = ""
    update = ""
    """
