import Foundation
import plate
import Interfaces
import Structures

public struct RelaunchConfig: Codable, Sendable {
    public var enable: Bool
    public var target: String?

    public init(enable: Bool = false, target: String? = nil) {
        self.enable = enable
        self.target = target
    }
}

public struct RenewableObject: Codable, Sendable {
    public var path: String
    public var compilable: Bool?
    public var relaunch: RelaunchConfig?
    public var ignore: Bool?

    public init(
        path: String,
        compilable: Bool? = nil,
        relaunch: RelaunchConfig? = nil,
        ignore: Bool? = nil
    ) {
        self.path = path
        self.compilable = compilable
        self.relaunch = relaunch
        self.ignore = ignore
    }
}
