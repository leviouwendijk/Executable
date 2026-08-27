import Foundation

public struct AppBundleInfo: Sendable {
    public let appBundleURL: URL
    public let bundleIdentifier: String?
    public let executableName: String

    public init(
        appBundleURL: URL,
        bundleIdentifier: String?,
        executableName: String
    ) {
        self.appBundleURL = appBundleURL
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
    }
}
