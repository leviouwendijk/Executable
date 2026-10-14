import Foundation
import Version

// unused so far?
public struct BuildObjectDetails: Codable {
    public let uuid: UUID
    public let name: String
    public let version: ObjectVersion
    public let latest: ObjectVersion
    public let details: String
    public let location: String
    public let date: Date

    public init(uuid: UUID, name: String, version: ObjectVersion, latest: ObjectVersion, details: String, location: String, date: Date) {
        self.uuid = uuid
        self.name = name
        self.version = version
        self.latest = latest
        self.details = details
        self.location = location
        self.date = date
    }
}

// for the .pkl file in the bm/index.pkl
public struct BuildObjectList: Codable {
    public let type: ExecutableObjectType
    public var objects: [BuildObjectDetails]

    public init(type: ExecutableObjectType, objects: [BuildObjectDetails]) {
        self.type = type
        self.objects = objects
    }
}
