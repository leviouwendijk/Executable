import Foundation
import Processes

public enum CodeSigning {
    public enum IdentityKind: String, Sendable, Codable, Hashable, CaseIterable {
        case appleDevelopment = "apple_development"
        case developerIDApplication = "developer_id_application"
        case appleDistribution = "apple_distribution"
        case other
    }

    public struct Identity: Sendable, Codable, Hashable {
        public let fingerprint: String
        public let name: String
        public let kind: IdentityKind
    }

    public enum Signer: Sendable, Hashable {
        case adHoc
        case identity(Identity)

        fileprivate var argument: String {
            switch self {
            case .adHoc: "-"
            case .identity(let identity): identity.fingerprint
            }
        }
    }

    public struct SignRequest: Sendable, Hashable {
        public let target: URL
        public let signer: Signer
        public let identifier: String?
        public let entitlements: URL?
        public let force: Bool
        public let hardenedRuntime: Bool

        public init(
            target: URL,
            signer: Signer,
            identifier: String? = nil,
            entitlements: URL? = nil,
            force: Bool = true,
            hardenedRuntime: Bool = false
        ) {
            self.target = target.standardizedFileURL
            self.signer = signer
            self.identifier = identifier
            self.entitlements = entitlements?.standardizedFileURL
            self.force = force
            self.hardenedRuntime = hardenedRuntime
        }
    }

    public struct Verification: Sendable, Hashable {
        public let target: URL
        public let valid: Bool
        public let exitCode: Int32?
        public let output: String
    }

    public struct Inspection: Sendable, Hashable {
        public let target: URL
        public let signed: Bool
        public let identifier: String?
        public let teamIdentifier: String?
        public let authorities: [String]
        public let adHoc: Bool
        public let designatedRequirement: String?
        public let entitlements: String?
        public let rawDetails: String
    }

    public struct SignResult: Sendable, Hashable {
        public let target: URL
        public let signer: Signer
        public let verification: Verification
        public let inspection: Inspection
    }

    public static func identities() async throws -> [Identity] {
        let result = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/security"),
                arguments: ["find-identity", "-v", "-p", "codesigning"],
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )
        let output = combined(result.stdoutText, result.stderrText)
        guard result.isSuccess else {
            throw CodeSigningError.commandFailed(
                operation: "discover code-signing identities",
                exitCode: result.exitCode,
                output: output
            )
        }
        return parseIdentities(output)
    }

    public static func resolveUniqueIdentity(kind: IdentityKind) async throws -> Identity {
        let matches = try await identities().filter { $0.kind == kind }
        guard !matches.isEmpty else {
            throw CodeSigningError.identityNotFound(kind)
        }
        guard matches.count == 1 else {
            throw CodeSigningError.ambiguousIdentities(
                kind: kind,
                identities: matches.map(\.name)
            )
        }
        return matches[0]
    }

    public static func verify(_ target: URL) async throws -> Verification {
        let target = try existing(target)
        let result = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/codesign"),
                arguments: ["--verify", "--strict", "--verbose=4", target.path],
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )
        return Verification(
            target: target,
            valid: result.isSuccess,
            exitCode: result.exitCode,
            output: combined(result.stdoutText, result.stderrText)
        )
    }

    public static func inspect(_ target: URL) async throws -> Inspection {
        let target = try existing(target)
        let display = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/codesign"),
                arguments: ["-d", "--verbose=4", target.path],
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )
        let details = combined(display.stdoutText, display.stderrText)
        guard display.isSuccess else {
            return Inspection(
                target: target,
                signed: false,
                identifier: nil,
                teamIdentifier: nil,
                authorities: [],
                adHoc: false,
                designatedRequirement: nil,
                entitlements: nil,
                rawDetails: details
            )
        }

        let requirement = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/codesign"),
                arguments: ["-d", "-r", "-", target.path],
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )
        let entitlements = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/codesign"),
                arguments: ["-d", "--entitlements", ":-", target.path],
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )

        return parseInspection(
            target: target,
            details: details,
            designatedRequirement: requirement.isSuccess
                ? parseRequirement(combined(requirement.stdoutText, requirement.stderrText))
                : nil,
            entitlements: entitlements.isSuccess
                ? combined(entitlements.stdoutText, entitlements.stderrText).nonEmpty
                : nil
        )
    }

    public static func sign(_ request: SignRequest) async throws -> SignResult {
        let target = try existing(request.target)
        if let entitlements = request.entitlements {
            _ = try existing(entitlements, error: .entitlementsNotFound(entitlements))
        }

        var arguments = ["--sign", request.signer.argument]
        if request.force { arguments.append("--force") }
        if let identifier = request.identifier {
            arguments += ["--identifier", identifier]
        }
        if request.hardenedRuntime {
            arguments += ["--options", "runtime"]
        }
        if let entitlements = request.entitlements {
            arguments += ["--entitlements", entitlements.path]
        }
        arguments.append(target.path)

        let result = try await ProcessRunner().run(
            .init(
                executable: .path("/usr/bin/codesign"),
                arguments: arguments,
                io: .pipes,
                outputLimit: 1024 * 1024
            )
        )
        let output = combined(result.stdoutText, result.stderrText)
        guard result.isSuccess else {
            throw CodeSigningError.commandFailed(
                operation: "sign \(target.lastPathComponent)",
                exitCode: result.exitCode,
                output: output
            )
        }

        let verification = try await verify(target)
        guard verification.valid else {
            throw CodeSigningError.verificationFailed(
                target: target,
                output: verification.output
            )
        }

        return SignResult(
            target: target,
            signer: request.signer,
            verification: verification,
            inspection: try await inspect(target)
        )
    }

    package static func parseIdentities(_ output: String) -> [Identity] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let numberedEnd = line.firstIndex(of: ")"),
                let openingQuote = line[line.index(after: numberedEnd)...].firstIndex(of: "\""),
                let closingQuote = line.lastIndex(of: "\""),
                openingQuote < closingQuote
            else { return nil }

            let fingerprint = String(line[line.index(after: numberedEnd)..<openingQuote])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(line[line.index(after: openingQuote)..<closingQuote])
            guard !fingerprint.isEmpty, !name.isEmpty else { return nil }

            return Identity(
                fingerprint: fingerprint,
                name: name,
                kind: identityKind(name)
            )
        }
    }

    package static func parseInspection(
        target: URL,
        details: String,
        designatedRequirement: String?,
        entitlements: String?
    ) -> Inspection {
        let team = firstValue(prefix: "TeamIdentifier=", in: details)
        return Inspection(
            target: target,
            signed: true,
            identifier: firstValue(prefix: "Identifier=", in: details),
            teamIdentifier: team.flatMap { $0 == "not set" ? nil : $0 },
            authorities: values(prefix: "Authority=", in: details),
            adHoc: details.contains("Signature=adhoc"),
            designatedRequirement: designatedRequirement,
            entitlements: entitlements,
            rawDetails: details
        )
    }
}

public enum CodeSigningError: Error, Sendable, LocalizedError, Equatable {
    case targetNotFound(URL)
    case entitlementsNotFound(URL)
    case identityNotFound(CodeSigning.IdentityKind)
    case ambiguousIdentities(kind: CodeSigning.IdentityKind, identities: [String])
    case commandFailed(operation: String, exitCode: Int32?, output: String)
    case verificationFailed(target: URL, output: String)

    public var errorDescription: String? {
        switch self {
        case .targetNotFound(let target):
            "Code-signing target not found: \(target.path)"
        case .entitlementsNotFound(let entitlements):
            "Code-signing entitlements file not found: \(entitlements.path)"
        case .identityNotFound(let kind):
            "No valid \(kind.rawValue) code-signing identity was found."
        case .ambiguousIdentities(let kind, let identities):
            "Multiple valid \(kind.rawValue) code-signing identities were found: \(identities.joined(separator: ", "))."
        case .commandFailed(let operation, let exitCode, let output):
            "\(operation) failed (exit \(exitCode.map { String($0) } ?? "signal")): \(output)"
        case .verificationFailed(let target, let output):
            "Code-signature verification failed for \(target.path): \(output)"
        }
    }
}

private extension CodeSigning {
    static func identityKind(_ name: String) -> IdentityKind {
        if name.hasPrefix("Apple Development:") { return .appleDevelopment }
        if name.hasPrefix("Developer ID Application:") { return .developerIDApplication }
        if name.hasPrefix("Apple Distribution:") { return .appleDistribution }
        return .other
    }

    static func existing(
        _ url: URL,
        error: CodeSigningError? = nil
    ) throws -> URL {
        let url = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw error ?? .targetNotFound(url)
        }
        return url
    }

    static func firstValue(prefix: String, in text: String) -> String? {
        values(prefix: prefix, in: text).first
    }

    static func values(prefix: String, in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(prefix) else { return nil }
            return String(line.dropFirst(prefix.count))
        }
    }

    static func parseRequirement(_ output: String) -> String? {
        guard let range = output.range(of: "designated =>") else {
            return output.nonEmpty
        }
        return String(output[range.upperBound...]).nonEmpty
    }

    static func combined(_ stdout: String, _ stderr: String) -> String {
        [stdout.nonEmpty, stderr.nonEmpty]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
