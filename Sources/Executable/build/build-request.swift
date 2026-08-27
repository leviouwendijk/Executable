import Foundation
import Path

public extension Build {
    struct Request: Sendable {
        public enum Source: Sendable {
            case direct(arguments: [String])
            case buildObject(url: URL, arguments: [String])

            public var arguments: [String] {
                switch self {
                case .direct(let arguments):
                    return arguments

                case .buildObject(_, let arguments):
                    return arguments
                }
            }

            public var description: String {
                switch self {
                case .direct:
                    return "direct invocation"

                case .buildObject:
                    return "build-object.pkl"
                }
            }
        }

        public struct Selection: Sendable {
            public let products: Set<String>
            public let legacyTargets: Set<String>
            public let skippedProducts: Set<String>
            public let legacySkippedTargets: Set<String>
            public let cliOnly: Bool
            public let keepApps: Bool
            public let destinationMappings: [String: URL]

            public init(
                products: Set<String> = [],
                legacyTargets: Set<String> = [],
                skippedProducts: Set<String> = [],
                legacySkippedTargets: Set<String> = [],
                cliOnly: Bool = false,
                keepApps: Bool = false,
                destinationMappings: [String: URL] = [:]
            ) {
                self.products = products
                self.legacyTargets = legacyTargets
                self.skippedProducts = skippedProducts
                self.legacySkippedTargets = legacySkippedTargets
                self.cliOnly = cliOnly
                self.keepApps = keepApps
                self.destinationMappings = destinationMappings
            }

            public var requiresResolution: Bool {
                !products.isEmpty
                    || !legacyTargets.isEmpty
                    || !skippedProducts.isEmpty
                    || !legacySkippedTargets.isEmpty
                    || cliOnly
                    || keepApps
                    || !destinationMappings.isEmpty
            }
        }

        public let project: URL
        public let config: Config
        public let destination: URL
        public let deploy: Bool
        public let selection: Selection
        public let source: Source

        public init(
            project: URL,
            config: Config,
            destination: URL = Build.defaultDeploymentDirectory,
            deploy: Bool = true,
            selection: Selection = .init(),
            source: Source = .direct(arguments: [])
        ) {
            self.project = project
            self.config = config
            self.destination = destination
            self.deploy = deploy
            self.selection = selection
            self.source = source
        }
    }

    static var defaultDeploymentDirectory: URL {
        PathAnchor.home.directory_url
            .appendingPathComponent(
                "sbm-bin",
                isDirectory: true
            )
    }
}
