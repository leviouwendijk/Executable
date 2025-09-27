import Foundation

public enum ObjectRenewerError: Error, LocalizedError, Sendable {
    case compilableNotConfigured(String)      // path
    // case compilableDisabled(String)           // path
    case directoryNotFound(String)            // expanded path
    case cannotCompile(URL, String)           // dir, message

    public var errorDescription: String? {
        switch self {
        case .compilableNotConfigured(let path):
            return "Compilable flag not configured for: \(path)"
        // case .compilableDisabled(let path):
        //     return "Compilation disabled for: \(path)"
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .cannotCompile(let dir, let msg):
            return "Compilation failed in \(dir.path): \(msg)"
        }
    }
}
