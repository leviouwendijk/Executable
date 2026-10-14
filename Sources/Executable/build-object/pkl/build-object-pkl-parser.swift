import Foundation
import Version
import Parsers

/// Compatibility entry point for the build-object subset, backed by Parsers.Pkl.
/// New callers should prefer the parse methods on the Version models.
public final class PklParser {
    public let input: String
    public private(set) var idx: String.Index

    public init(_ text: String) {
        input = text
        idx = text.startIndex
    }

    public func parseBuildObject() throws -> BuildObjectConfiguration {
        let result = try BuildObjectPklDecoder.modern(String(input[idx...]))
        idx = input.endIndex
        return result
    }

    public func parseLegacyBuildObject() throws -> BuildObjectConfiguration.LegacyObject {
        let result = try BuildObjectPklDecoder.legacy(String(input[idx...]))
        idx = input.endIndex
        return result
    }

    public func parseCompiledBuildObject() throws -> CompiledLocalBuildObject {
        let result = try BuildObjectPklDecoder.compiled(String(input[idx...]))
        idx = input.endIndex
        return result
    }
}
