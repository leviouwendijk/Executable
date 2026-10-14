import Foundation
import Version

public extension BuildObjectConfiguration {
    static func parse(_ source: String) throws -> Self {
        try BuildObjectPklDecoder.modern(source)
    }
}

public extension BuildObjectConfiguration.LegacyObject {
    static func parse(_ source: String) throws -> Self {
        try BuildObjectPklDecoder.legacy(source)
    }
}

public extension CompiledLocalBuildObject {
    static func parse(_ source: String) throws -> Self {
        try BuildObjectPklDecoder.compiled(source)
    }
}
