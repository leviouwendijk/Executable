import Version

public struct ProjectVersions: Codable, Sendable {
    // public var built: ObjectVersion
    // public var release: ObjectVersion
    public var release: ObjectVersion
    
    public init(
        // built: ObjectVersion,
        // release: ObjectVersion
        release: ObjectVersion
    ) {
        // self.built = built
        // self.release = release
        self.release = release
    }
}

// public enum VersionReference: String, RawRepresentable, Codable, CaseIterable, Sendable {
//     case built
//     case repository
// }

// public struct ProjectVersions: Codable, Sendable {
//     public var built: ObjectVersion
//     public var repository: ObjectVersion
    
//     public init(
//         built: ObjectVersion,
//         repository: ObjectVersion
//     ) {
//         self.built = built
//         self.repository = repository
//     }
// }
