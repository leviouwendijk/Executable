import Foundation
import Version

public enum ExecutableObjectType: String, RawRepresentable, Codable, Sendable {
    case binary
    case application
    case script
    case specification
    case resource
}

extension Array where Element == ExecutableObjectType {
    public func set() -> Set<String> {
        var acc: Set<String> = []
        for i in self {
            let string = i.rawValue
            acc.insert(string)
        }
        return acc
    }
}
