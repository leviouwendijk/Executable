import Foundation

/// SwiftPM manifest declaration semantics produced by `swift package dump-package`.
///
/// This type intentionally represents what the root manifest declares. Resolved
/// transitive package topology belongs to `SwiftPackageGraph` instead.
public struct SwiftPackageManifest:
    Sendable,
    Hashable
{
    public struct Platform:
        Sendable,
        Hashable
    {
        public let name: String
        public let version: String

        public init(
            name: String,
            version: String
        ) {
            self.name = name
            self.version = version
        }
    }

    /// One package dependency declaration retained from the manifest.
    ///
    /// Version resolution deliberately does not live here. `Package.graph(at:)`
    /// reports the packages SwiftPM actually resolved.
    public struct Dependency:
        Sendable,
        Hashable
    {
        public enum Kind:
            String,
            Sendable,
            Hashable
        {
            case sourceControl
            case fileSystem
            case registry
            case other
        }

        public let kind: Kind
        public let identity: String?
        public let location: String?

        public init(
            kind: Kind,
            identity: String? = nil,
            location: String? = nil
        ) {
            self.kind = kind
            self.identity = identity
            self.location = location
        }
    }

    public struct Product:
        Sendable,
        Hashable
    {
        public enum Kind:
            String,
            Sendable,
            Hashable
        {
            case executable
            case library
            case plugin
            case snippet
            case test
            case `macro`
            case other
        }

        public let name: String
        public let kind: Kind
        public let targets: [String]

        public init(
            name: String,
            kind: Kind,
            targets: [String]
        ) {
            self.name = name
            self.kind = kind
            self.targets = targets
        }
    }

    public struct Target:
        Sendable,
        Hashable
    {
        public struct Dependency:
            Sendable,
            Hashable
        {
            public enum Kind:
                String,
                Sendable,
                Hashable
            {
                case target
                case product
                case byName
                case other
            }

            public let kind: Kind
            public let name: String
            public let package: String?

            public init(
                kind: Kind,
                name: String,
                package: String? = nil
            ) {
                self.kind = kind
                self.name = name
                self.package = package
            }
        }

        public let name: String
        public let type: String
        public let path: String?
        public let dependencies: [Dependency]

        public init(
            name: String,
            type: String,
            path: String?,
            dependencies: [Dependency] = []
        ) {
            self.name = name
            self.type = type
            self.path = path
            self.dependencies = dependencies
        }
    }

    public let name: String
    public let toolsVersion: String?
    public let platforms: [Platform]
    public let dependencies: [Dependency]
    public let products: [Product]
    public let targets: [Target]

    public init(
        name: String,
        toolsVersion: String? = nil,
        platforms: [Platform] = [],
        dependencies: [Dependency] = [],
        products: [Product],
        targets: [Target]
    ) {
        self.name = name
        self.toolsVersion = toolsVersion
        self.platforms = platforms
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
    }
}

extension SwiftPackageManifest {
    init(
        dump data: Data,
        fallbackName: String
    ) throws {
        let dump = try JSONDecoder().decode(
            SwiftPackageManifestDump.self,
            from: data
        )

        name = dump.name
            ?? fallbackName

        toolsVersion = dump.toolsVersion?.version

        platforms = (dump.platforms ?? []).map { platform in
            Platform(
                name: platform.platformName,
                version: platform.version
            )
        }

        dependencies = (dump.dependencies ?? []).map(
            Self.packageDependency
        )

        products = (dump.products ?? []).map { product in
            Product(
                name: product.name,
                kind: product.type?.kind ?? .other,
                targets: product.targets
            )
        }

        targets = (dump.targets ?? []).map { target in
            Target(
                name: target.name,
                type: target.type,
                path: target.path,
                dependencies: (target.dependencies ?? []).compactMap(
                    Self.targetDependency
                )
            )
        }
    }
}

private extension SwiftPackageManifest {
    static func packageDependency(
        _ value: SwiftPackageManifestJSONValue
    ) -> Dependency {
        guard case .object(let object) = value else {
            return .init(
                kind: .other
            )
        }

        let kind: Dependency.Kind
        let payload: SwiftPackageManifestJSONValue

        if let value = object["sourceControl"] {
            kind = .sourceControl
            payload = value
        } else if let value = object["fileSystem"] {
            kind = .fileSystem
            payload = value
        } else if let value = object["registry"] {
            kind = .registry
            payload = value
        } else if object["url"] != nil {
            kind = .sourceControl
            payload = value
        } else if object["path"] != nil {
            kind = .fileSystem
            payload = value
        } else {
            kind = .other
            payload = value
        }

        let location = payload.string(
            forKeys: [
                "location",
                "url",
                "path",
            ]
        )

        let explicitIdentity = payload.string(
            forKeys: [
                "identity",
                "id",
            ]
        )

        return .init(
            kind: kind,
            identity:
                explicitIdentity
                ?? dependencyIdentity(
                    from: location
                ),
            location: location
        )
    }

    static func dependencyIdentity(
        from location: String?
    ) -> String? {
        guard
            let location,
            !location.isEmpty
        else {
            return nil
        }

        let component = location
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(
                of: ".git",
                with: ""
            )

        guard
            let component,
            !component.isEmpty
        else {
            return nil
        }

        return component.lowercased()
    }

    static func targetDependency(
        _ value: SwiftPackageManifestJSONValue
    ) -> Target.Dependency? {
        guard case .object(let object) = value else {
            return nil
        }

        let kind: Target.Dependency.Kind
        let payload: SwiftPackageManifestJSONValue

        if let value = object["target"] {
            kind = .target
            payload = value
        } else if let value = object["product"] {
            kind = .product
            payload = value
        } else if let value = object["byName"] {
            kind = .byName
            payload = value
        } else {
            guard
                let entry = object
                    .sorted(
                        by: {
                            $0.key < $1.key
                        }
                    )
                    .first
            else {
                return nil
            }

            kind = .other
            payload = entry.value
        }

        guard
            let values = payload.arrayValue,
            let name = values.first?.stringValue
        else {
            return nil
        }

        let package: String?

        if kind == .product,
           values.indices.contains(1)
        {
            package = values[1].stringValue
        } else {
            package = nil
        }

        return .init(
            kind: kind,
            name: name,
            package: package
        )
    }
}

private struct SwiftPackageManifestDump:
    Decodable
{
    struct ToolsVersion:
        Decodable
    {
        let version: String

        enum CodingKeys:
            String,
            CodingKey
        {
            case version = "_version"
        }
    }

    struct Platform:
        Decodable
    {
        let platformName: String
        let version: String
    }

    struct Product:
        Decodable
    {
        let name: String
        let type: ProductType?
        let targets: [String]
    }

    struct ProductType:
        Decodable
    {
        let kind: SwiftPackageManifest.Product.Kind

        init(
            from decoder: Decoder
        ) throws {
            let container = try decoder.container(
                keyedBy: DynamicCodingKey.self
            )

            kind = container.allKeys
                .compactMap {
                    SwiftPackageManifest.Product.Kind(
                        rawValue: $0.stringValue
                    )
                }
                .first
                ?? .other
        }
    }

    struct Target:
        Decodable
    {
        let name: String
        let type: String
        let path: String?
        let dependencies: [SwiftPackageManifestJSONValue]?
    }

    let name: String?
    let toolsVersion: ToolsVersion?
    let platforms: [Platform]?
    let dependencies: [SwiftPackageManifestJSONValue]?
    let products: [Product]?
    let targets: [Target]?
}

private enum SwiftPackageManifestJSONValue:
    Decodable
{
    case object([String: Self])
    case array([Self])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(
        from decoder: Decoder
    ) throws {
        if let container = try? decoder.container(
            keyedBy: DynamicCodingKey.self
        ) {
            var object: [String: Self] = [:]

            for key in container.allKeys {
                object[key.stringValue] = try container.decode(
                    Self.self,
                    forKey: key
                )
            }

            self = .object(
                object
            )
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var values: [Self] = []

            while !container.isAtEnd {
                values.append(
                    try container.decode(
                        Self.self
                    )
                )
            }

            self = .array(
                values
            )
            return
        }

        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(
            String.self
        ) {
            self = .string(
                value
            )
        } else if let value = try? container.decode(
            Bool.self
        ) {
            self = .boolean(
                value
            )
        } else {
            self = .number(
                try container.decode(
                    Double.self
                )
            )
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }

        return value
    }

    var arrayValue: [Self]? {
        guard case .array(let value) = self else {
            return nil
        }

        return value
    }

    func string(
        forKeys keys: [String]
    ) -> String? {
        switch self {
        case .object(let object):
            for key in keys {
                if let value = object[key],
                   let string = value.firstString
                {
                    return string
                }
            }

            for key in object.keys.sorted() {
                if let string = object[key]?.string(
                    forKeys: keys
                ) {
                    return string
                }
            }

            return nil

        case .array(let values):
            for value in values {
                if let string = value.string(
                    forKeys: keys
                ) {
                    return string
                }
            }

            return nil

        case .string,
             .number,
             .boolean,
             .null:
            return nil
        }
    }

    var firstString: String? {
        switch self {
        case .string(let value):
            return value

        case .array(let values):
            return values.lazy.compactMap(
                \.firstString
            ).first

        case .object(let object):
            return object.keys
                .sorted()
                .lazy
                .compactMap {
                    object[$0]?.firstString
                }
                .first

        case .number,
             .boolean,
             .null:
            return nil
        }
    }
}

private struct DynamicCodingKey:
    CodingKey
{
    let stringValue: String
    let intValue: Int?

    init?(
        stringValue: String
    ) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(
        intValue: Int
    ) {
        stringValue = String(
            intValue
        )
        self.intValue = intValue
    }
}
