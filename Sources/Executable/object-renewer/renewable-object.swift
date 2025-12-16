import Foundation

public struct RelaunchConfig: Codable, Sendable {
    public var enable: Bool
    public var target: String?

    public init(enable: Bool = false, target: String? = nil) {
        self.enable = enable
        self.target = target
    }
}

public struct ObjectComparisonCriteria: Codable, Sendable {
    public var upstream: Bool
    public var compiled: Bool
    
    public init(
        upstream: Bool = true,
        compiled: Bool = true
    ) {
        self.upstream = upstream
        self.compiled = compiled
    }
}

public struct RenewableObject: Codable, Sendable {
    public var path: String
    public var compilable: Bool?
    public var relaunch: RelaunchConfig?
    public var ignore: Bool?
    public var criteria: ObjectComparisonCriteria

    public init(
        path: String,
        compilable: Bool? = nil,
        relaunch: RelaunchConfig? = nil,
        ignore: Bool? = nil,
        criteria: ObjectComparisonCriteria = .init()
    ) {
        self.path = path
        self.compilable = compilable
        self.relaunch = relaunch
        self.ignore = ignore
        self.criteria = criteria
    }
}
