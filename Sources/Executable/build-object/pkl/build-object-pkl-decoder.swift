import Foundation
import Version
import Parsers

/// Consumer-specific Pkl mapping and legacy rules. Parsers owns syntax and Codable.
/// This layer intentionally does not implement a second AST walking decoder.
enum BuildObjectPklDecoder {
    private static let coding = PklCoding(duplicateKeyStrategy: .lastWins)

    private struct ModernFields: Decodable {
        let uuid: String
        let name: String
        let types: [ExecutableObjectType]
        let versions: ProjectVersions
        let compile: CompileFields?
        let tests: TestFields?
        let details: String
        let author: String
        let update: String
    }

    private struct LegacyFields: Decodable {
        let uuid: String
        let name: String
        let type: ExecutableObjectType
        let version: ObjectVersion
        let details: String
        let author: String
        let update: String
    }

    private struct CompiledEnvelope: Decodable {
        let compiled: CompiledFields
    }

    private struct CompiledFields: Decodable {
        let version: ObjectVersion
        let arguments: [String]
    }

    private struct CompileFields: Decodable {
        let use: BooleanOrInteger?
        let arguments: [String]?
    }

    private struct TestFields: Decodable {
        let primary: String
        let groups: [String: [String]]?
    }

    private struct BooleanOrInteger: Decodable {
        let value: Bool
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                value = bool
            } else {
                value = try container.decode(Int.self) != 0
            }
        }
    }

    static func modern(_ text: String) throws -> BuildObjectConfiguration {
        let document = try document(text)
        try validate_modern_sections(document)
        let dto: ModernFields = try decode(ModernFields.self, document)
        let uuid = try parsed_uuid(dto.uuid)
        guard !dto.types.isEmpty else { throw PklParserError.missingField("types") }
        return BuildObjectConfiguration(
            uuid: uuid,
            name: dto.name,
            types: dto.types,
            versions: dto.versions,
            compile: .init(use: dto.compile?.use?.value ?? false, arguments: dto.compile?.arguments ?? []),
            details: dto.details,
            author: dto.author,
            update: dto.update,
            tests: dto.tests.map { TestConfiguration(primary: $0.primary, groups: $0.groups ?? [:]) }
        )
    }

    static func legacy(_ text: String) throws -> BuildObjectConfiguration.LegacyObject {
        let dto: LegacyFields = try decode(LegacyFields.self, document(text))
        return .init(
            uuid: try parsed_uuid(dto.uuid),
            name: dto.name,
            type: dto.type,
            version: dto.version,
            details: dto.details,
            author: dto.author,
            update: dto.update
        )
    }

    static func compiled(_ text: String) throws -> CompiledLocalBuildObject {
        let parsed = try document(text)
        if let node = parsed.entries.last(where: { $0.name == "compiled" }) {
            let entries = try block(node)
            try allowed(entries, ["version", "arguments"], context: "compiled")
            if let version = entries.last(where: { $0.name == "version" }) {
                try allowed(try block(version), ["major", "minor", "patch"], context: "version")
            }
        }
        let dto: CompiledEnvelope = try decode(CompiledEnvelope.self, parsed)
        return CompiledLocalBuildObject(version: dto.compiled.version, arguments: dto.compiled.arguments)
    }

    private static func document(_ text: String) throws -> Pkl.Document {
        do { return try Pkl.parse(text) }
        catch let error as Pkl.SyntaxFailure { throw PklParserError.syntaxError(error.description) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ doc: Pkl.Document) throws -> T {
        do { return try coding.decode(type, from: doc) }
        catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, _):
                throw PklParserError.missingField(key.stringValue)
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                let field = context.codingPath.last?.stringValue ?? "pkl"
                throw PklParserError.invalidValue(field: field, value: context.debugDescription)
            @unknown default:
                throw PklParserError.syntaxError(String(describing: error))
            }
        }
    }

    private static func parsed_uuid(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw PklParserError.invalidValue(field: "uuid", value: value)
        }
        return uuid
    }

    private static func block(_ entry: Pkl.Entry) throws -> [Pkl.Entry] {
        guard case .block(let entries) = entry.value else {
            throw PklParserError.invalidValue(field: entry.name, value: String(describing: entry.value))
        }
        return entries
    }

    private static func allowed(_ entries: [Pkl.Entry], _ fields: Set<String>, context: String) throws {
        for entry in entries where !fields.contains(entry.name) {
            throw PklParserError.syntaxError("Unknown \(context) field '\(entry.name)'")
        }
    }

    private static func validate_modern_sections(_ document: Pkl.Document) throws {
        if let versions = document.entries.last(where: { $0.name == "versions" }) {
            let entries = try block(versions)
            try allowed(entries, ["release"], context: "versions")
            if let release = entries.last(where: { $0.name == "release" }) {
                try allowed(try block(release), ["major", "minor", "patch"], context: "release")
            }
        }
        if let compile = document.entries.last(where: { $0.name == "compile" }) {
            try allowed(try block(compile), ["use", "arguments"], context: "compile")
        }
        if let tests = document.entries.last(where: { $0.name == "tests" }) {
            let entries = try block(tests)
            try allowed(entries, ["primary", "groups"], context: "tests")
            if let groups = entries.last(where: { $0.name == "groups" }) {
                _ = try block(groups)
            }
        }
    }
}
