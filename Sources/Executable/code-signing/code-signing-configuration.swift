import Foundation

public extension CodeSigning {
    enum IdentitySelector: Sendable, Hashable {
        case adHoc
        case kind(IdentityKind)
        case fingerprint(String)

        public init(argument value: String) throws {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch normalized {
            case "ad-hoc", "adhoc", "-":
                self = .adHoc

            case "apple-development", "apple_development":
                self = .kind(.appleDevelopment)

            case "developer-id-application", "developer_id_application":
                self = .kind(.developerIDApplication)

            case "apple-distribution", "apple_distribution":
                self = .kind(.appleDistribution)

            default:
                if normalized.hasPrefix("fingerprint:") {
                    let fingerprint = String(
                        value.dropFirst("fingerprint:".count)
                    )
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !fingerprint.isEmpty else {
                        throw CodeSigningConfigurationError.invalidIdentitySelector(
                            value
                        )
                    }

                    self = .fingerprint(fingerprint)
                    return
                }

                let compact = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if compact.count == 40,
                   compact.allSatisfy({ $0.isHexDigit })
                {
                    self = .fingerprint(compact)
                    return
                }

                throw CodeSigningConfigurationError.invalidIdentitySelector(
                    value
                )
            }
        }

        public var argumentValue: String {
            switch self {
            case .adHoc:
                "ad-hoc"

            case .kind(.appleDevelopment):
                "apple-development"

            case .kind(.developerIDApplication):
                "developer-id-application"

            case .kind(.appleDistribution):
                "apple-distribution"

            case .kind(.other):
                "other"

            case .fingerprint(let fingerprint):
                "fingerprint:\(fingerprint)"
            }
        }
    }

    struct Configuration: Sendable, Hashable {
        public let identity: IdentitySelector
        public let identifier: String?
        public let entitlements: URL?
        public let hardenedRuntime: Bool

        public init(
            identity: IdentitySelector,
            identifier: String? = nil,
            entitlements: URL? = nil,
            hardenedRuntime: Bool = false
        ) {
            self.identity = identity
            self.identifier = identifier
            self.entitlements = entitlements?.standardizedFileURL
            self.hardenedRuntime = hardenedRuntime
        }
    }

    static func resolve(
        _ selector: IdentitySelector
    ) async throws -> Signer {
        switch selector {
        case .adHoc:
            return .adHoc

        case .kind(let kind):
            return .identity(
                try await resolveUniqueIdentity(
                    kind: kind
                )
            )

        case .fingerprint(let fingerprint):
            let identities = try await identities()
            guard let identity = identities.first(where: {
                $0.fingerprint.compare(
                    fingerprint,
                    options: .caseInsensitive
                ) == .orderedSame
            }) else {
                throw CodeSigningConfigurationError.identityFingerprintNotFound(
                    fingerprint
                )
            }

            return .identity(identity)
        }
    }
}

public enum CodeSigningConfigurationError:
    Error,
    Sendable,
    LocalizedError,
    Equatable
{
    case invalidIdentitySelector(String)
    case identityFingerprintNotFound(String)
    case signingOptionsRequireIdentity

    public var errorDescription: String? {
        switch self {
        case .invalidIdentitySelector(let value):
            "Invalid code-signing identity selector '\(value)'."

        case .identityFingerprintNotFound(let fingerprint):
            "No valid code-signing identity with fingerprint '\(fingerprint)' was found."

        case .signingOptionsRequireIdentity:
            "Code-signing options require --sign <identity>."
        }
    }
}
