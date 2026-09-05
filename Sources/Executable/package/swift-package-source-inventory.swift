import Foundation

/// SwiftPM-resolved source membership for the root package.
///
/// Unlike `SwiftPackageManifest`, this type describes the source files SwiftPM
/// actually assigns to each target after applying target paths, explicit source
/// lists, exclusions, and SwiftPM's package layout conventions.
///
/// Resolved dependency-package topology remains the responsibility of
/// `SwiftPackageGraph`.
public struct SwiftPackageSourceInventory:
    Sendable,
    Hashable
{
    public struct Target:
        Sendable,
        Hashable
    {
        public let name: String
        public let type: String
        public let directory: URL?
        public let sourceFiles: [URL]

        public init(
            name: String,
            type: String,
            directory: URL? = nil,
            sourceFiles: [URL] = []
        ) {
            self.name = name
            self.type = type
            self.directory = directory?.standardizedFileURL
            self.sourceFiles = sourceFiles
                .map(\.standardizedFileURL)
                .sorted {
                    $0.path < $1.path
                }
        }
    }

    public let packageName: String
    public let targets: [Target]

    public init(
        packageName: String,
        targets: [Target]
    ) {
        self.packageName = packageName
        self.targets = targets.sorted {
            targetKey($0) < targetKey($1)
        }
    }

    public func target(
        named name: String
    ) -> Target? {
        targets.first {
            $0.name == name
        }
    }
}

extension SwiftPackageSourceInventory {
    init(
        descriptionData data: Data,
        packageDirectory: URL
    ) throws {
        let jsonData = try Self.jsonObjectData(
            from: data
        )

        let description = try JSONDecoder().decode(
            SwiftPackageDescriptionDump.self,
            from: jsonData
        )

        let root = packageDirectory
            .standardizedFileURL

        self.init(
            packageName: description.name,
            targets: description.targets.map { target in
                let directory = target.path.map {
                    resolvedFileURL(
                        $0,
                        relativeTo: root
                    )
                }

                let sourceBase = directory
                    ?? root

                return Target(
                    name: target.name,
                    type: target.type,
                    directory: directory,
                    sourceFiles: (target.sources ?? []).map {
                        resolvedFileURL(
                            $0,
                            relativeTo: sourceBase
                        )
                    }
                )
            }
        )
    }
}

private extension SwiftPackageSourceInventory {
    static func jsonObjectData(
        from data: Data
    ) throws -> Data {
        guard
            let text = String(
                data: data,
                encoding: .utf8
            ),
            let start = text.firstIndex(
                of: "{"
            ),
            let end = text.lastIndex(
                of: "}"
            ),
            start <= end
        else {
            throw SwiftPackageSourceInventoryError.decodeFailed(
                message: "SwiftPM output did not contain a JSON object."
            )
        }

        return Data(
            text[start...end].utf8
        )
    }
}

private struct SwiftPackageDescriptionDump:
    Decodable
{
    struct Target:
        Decodable
    {
        let name: String
        let type: String
        let path: String?
        let sources: [String]?
    }

    let name: String
    let targets: [Target]
}

private func resolvedFileURL(
    _ path: String,
    relativeTo base: URL
) -> URL {
    if (path as NSString).isAbsolutePath {
        return URL(
            fileURLWithPath: path
        )
        .standardizedFileURL
    }

    return base
        .appendingPathComponent(
            path
        )
        .standardizedFileURL
}

private func targetKey(
    _ target: SwiftPackageSourceInventory.Target
) -> String {
    [
        target.name,
        target.type,
        target.directory?.path ?? "",
    ]
        .joined(
            separator: "\u{1F}"
        )
}
