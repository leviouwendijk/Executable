import Foundation
import Frame

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
            case "ad-hoc", "ad_hoc", "adhoc", "-":
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

    /// What a build does when this machine has no identity matching the selector
    /// (`.sign.missing` in package.frame). An ambiguous identity always fails.
    enum MissingIdentity: String, Sendable, Hashable, Codable, CaseIterable, FrameDescribable {
        /// Stop the build (the default, and what deploy hosts want).
        case fail
        /// Sign ad-hoc instead, with a warning: the binary runs, but its signature changes every build.
        case adHoc = "ad_hoc"
        /// Leave the product unsigned, with a warning.
        case skip

        public static var frameSchema: Frame.Schema {
            .members(of: Self.self, summary: "What a build does when this machine lacks the identity.", summaries: [
                .fail: "Stop the build (default).",
                .adHoc: "Sign ad-hoc instead, with a warning.",
                .skip: "Leave the product unsigned, with a warning.",
            ])
        }
    }

    struct Configuration: Sendable, Hashable {
        public let identity: IdentitySelector
        public let identifier: String?
        public let entitlements: URL?
        public let hardenedRuntime: Bool
        public let missing: MissingIdentity

        public init(
            identity: IdentitySelector,
            identifier: String? = nil,
            entitlements: URL? = nil,
            hardenedRuntime: Bool = false,
            missing: MissingIdentity = .fail
        ) {
            self.identity = identity
            self.identifier = identifier
            self.entitlements = entitlements?.standardizedFileURL
            self.hardenedRuntime = hardenedRuntime
            self.missing = missing
        }
    }

    /// What signing a product with `configuration` comes down to on this machine.
    enum Resolution: Sendable, Hashable {
        case sign(Signer)
        /// The identity is missing and `.missing` says what happens instead; `signer` nil means unsigned.
        case fallback(Signer?, reason: String)
    }

    /// The signer for `configuration`, applying `.missing` when this machine has no matching
    /// identity. Throws for `.fail`, and for every other resolution error.
    static func resolve(
        _ configuration: Configuration
    ) async throws -> Resolution {
        do {
            return .sign(try await resolve(configuration.identity))
        } catch let error where isMissingIdentity(error) {
            switch configuration.missing {
            case .fail: throw error
            case .adHoc: return .fallback(.adHoc, reason: error.localizedDescription)
            case .skip: return .fallback(nil, reason: error.localizedDescription)
            }
        }
    }

    static func isMissingIdentity(_ error: Error) -> Bool {
        switch error {
        case CodeSigningError.identityNotFound: true
        case CodeSigningConfigurationError.identityFingerprintNotFound: true
        default: false
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
