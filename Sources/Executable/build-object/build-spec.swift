import Foundation
import Version

@available(*, deprecated, message: "Superseded by BuildObjectConfiguration")
public struct BuildSpecification {
    public let version: BuildVersion
    public let name: String
    public let author: String
    public let description: String

    public init(
        version: BuildVersion,
        name: String,
        author: String = "",
        description: String = ""
    ) {
        self.version = version
        self.name = name
        self.author = author
        self.description = description
    }

    public func versionString() -> String {
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    public func appAndVersionString() -> String {
        return "\(name) \(version.major).\(version.minor).\(version.patch)"
    }

    // public init(fromPkl url: URL = URL(fileURLWithPath: "build-object.pkl")) throws {
    //     let cfg = try BuildObjectConfiguration.parse(from: url)

    //     self.version = BuildVersion(
    //         major: cfg.versions.built.major,
    //         minor: cfg.versions.built.minor,
    //         patch: cfg.versions.built.patch
    //     )
    //     self.name = cfg.name
    //     self.author = cfg.author
    //     self.description = cfg.details
    // }

    // use new separation of files
    public init(
        buildObjectPkl buildObjectUrl: URL = URL(fileURLWithPath: "build-object.pkl"),
        compiledPkl compiledUrl: URL = URL(fileURLWithPath: "compiled.pkl")
    ) throws {
        let compiled = try CompiledLocalBuildObject.parse(from: compiledUrl)

        self.version = BuildVersion(
            major: compiled.version.major,
            minor: compiled.version.minor,
            patch: compiled.version.patch
        )

        let buildObject = try BuildObjectConfiguration.parse(from: buildObjectUrl)

        self.name = buildObject.name
        self.author = buildObject.author
        self.description = buildObject.details
    }
}
