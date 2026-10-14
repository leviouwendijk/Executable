import Foundation
import Version

extension BuildObjectConfiguration {
    public struct LegacyObject: Codable, Sendable {
        public let uuid: UUID
        public let name: String
        public let type: ExecutableObjectType
        public let version: ObjectVersion
        public let details: String
        public let author: String
        public let update: String

        public init(
            uuid: UUID = UUID(),
            name: String,
            type: ExecutableObjectType,
            version: ObjectVersion,
            details: String,
            author: String,
            update: String
        ) {
            self.uuid = uuid
            self.name = name
            self.type = type
            self.version = version
            self.details = details
            self.author = author
            self.update = update
        }

        // turn legacy into modern struct
        public func modernize() -> BuildObjectConfiguration {
            return .init(
                uuid: uuid,
                name: name,
                types: [type],
                versions: ProjectVersions(
                    // built: ObjectVersion.default_version(for: .built),
                    // repository: version
                    release: version
                ),
                compile: .init(),
                details: details,
                author: author,
                update: update
            )
        }
    }
}
