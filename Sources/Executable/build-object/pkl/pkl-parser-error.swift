import Foundation
import Version

public enum PklParserError: Error, CustomStringConvertible {
    case ioError(String)
    case syntaxError(String)
    case missingField(String)
    case invalidValue(field: String, value: String)

    public var description: String {
        switch self {
        case .ioError(let msg):              return "I/O Error: \(msg)"
        case .syntaxError(let msg):          return "Syntax Error: \(msg)"
        case .missingField(let f):           return "Missing required field: \(f)"
        case .invalidValue(let f, let v):    return "Invalid value '\(v)' for field '\(f)'"
        }
    }
}
