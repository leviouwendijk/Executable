import Foundation

public enum ProcessEvaluatorError: Error, LocalizedError, Sendable {
    case notMacAppEnvironment(String)
    
    public var errorDescription: String? {
        switch self {
        case .notMacAppEnvironment(let msg): return msg
        }
    }
}
