import Foundation

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
        public let name: String
        public let type: String
        public let path: String?

        public init(
            name: String,
            type: String,
            path: String?
        ) {
            self.name = name
            self.type = type
            self.path = path
        }
    }

    public let name: String
    public let toolsVersion: String?
    public let platforms: [Platform]
    public let products: [Product]
    public let targets: [Target]

    public init(
        name: String,
        toolsVersion: String? = nil,
        platforms: [Platform] = [],
        products: [Product],
        targets: [Target]
    ) {
        self.name = name
        self.toolsVersion = toolsVersion
        self.platforms = platforms
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
                path: target.path
            )
        }
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
    }

    let name: String?
    let toolsVersion: ToolsVersion?
    let platforms: [Platform]?
    let products: [Product]?
    let targets: [Target]?
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
