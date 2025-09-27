import Foundation

public enum AppBundleResolverError: Error, LocalizedError, Sendable {
    case notFound(URL, String)
    case infoPlistUnreadable(URL)
    case missingExecutable(URL)
    
    public var errorDescription: String? {
        switch self {
        case let .notFound(dir, name):
            return "No \(name) found at \(dir.path)."
        case .infoPlistUnreadable(let url):
            return "Could not read Info.plist at \(url.path)."
        case .missingExecutable(let url):
            return "CFBundleExecutable missing for \(url.path)."
        }
    }
}
