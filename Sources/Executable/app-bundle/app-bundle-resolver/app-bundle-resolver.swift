import Foundation

public struct AppBundleResolver: Sendable {
    public init() {}
    
    public func resolve(
        directoryURL: URL,
        target: String?
    ) throws -> AppBundleInfo {
        let repoName    = directoryURL.lastPathComponent
        let inferredApp = repoName + ".app"
        
        let targetAppName = (target == "infer") ? inferredApp : (target ?? inferredApp)
        let appBundleName = targetAppName.hasSuffix(".app") ? targetAppName : targetAppName + ".app"
        let appBundleURL  = directoryURL.appendingPathComponent(appBundleName)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appBundleURL.path, isDirectory: &isDir), isDir.boolValue
        else { throw AppBundleResolverError.notFound(directoryURL, appBundleName) }
        
        // best-effort Info.plist read using Bundle
        guard let bundle = Bundle(url: appBundleURL) else {
            throw AppBundleResolverError.infoPlistUnreadable(appBundleURL)
        }
        guard let execName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
            !execName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AppBundleResolverError.missingExecutable(appBundleURL)
        }
        return .init(appBundleURL: appBundleURL, bundleIdentifier: bundle.bundleIdentifier, executableName: execName)
    }
}
