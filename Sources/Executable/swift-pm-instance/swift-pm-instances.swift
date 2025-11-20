import Foundation
import Interfaces
import plate
import Darwin

public struct SwiftPMProcess: Sendable, Hashable {
    public let pid: pid_t
    public let commandLine: String

    public init(pid: pid_t, commandLine: String) {
        self.pid = pid
        self.commandLine = commandLine
    }
}

public enum SwiftPMProcessError: Swift.Error, LocalizedError, Sendable {
    case failedToParsePID(String)
    case killFailed(pid: pid_t, signal: Int32, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .failedToParsePID(let raw):
            return "Failed to parse PID from line: \(raw)"
        case .killFailed(let pid, let signal, let err):
            return "kill(\(pid), \(signal)) failed with errno=\(err)"
        }
    }
}

public struct SwiftPMProcesses: Sendable {
    public init() {}

    /// Discover running Swift / SwiftPM-related processes.
    public func list(
        cwd overrideCWD: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let cwd = overrideCWD ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let result = try await sh(
            .zsh,
            "ps",
            ["ax", "-o", "pid=,command="],
            cwd: cwd
        )

        let text = result.stdoutText()
        var processes: [SwiftPMProcess] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let pidPart = parts.first else { continue }
            let cmdPart = parts.count > 1 ? String(parts[1]) : ""

            guard let pidInt = Int32(pidPart) else {
                continue
            }

            guard Self.isSwiftPMCommandLine(cmdPart) else { continue }

            processes.append(
                SwiftPMProcess(
                    pid: pidInt,
                    commandLine: cmdPart
                )
            )
        }

        return processes
    }

    /// Kill a single SwiftPM process.
    /// If `dryRun` is true, only logs what *would* be done, no signal is sent.
    public func kill(
        _ process: SwiftPMProcess,
        force: Bool = false,
        dryRun: Bool = false
    ) throws {
        let signal: Int32 = force ? SIGKILL : SIGTERM
        let sigName = force ? "SIGKILL" : "SIGTERM"

        if dryRun {
            printi("[dry-run] Would send \(sigName) to pid \(process.pid) – \(process.commandLine)")
            return
        }

        let r = Darwin.kill(process.pid, signal)
        if r != 0 {
            throw SwiftPMProcessError.killFailed(
                pid: process.pid,
                signal: signal,
                errno: errno
            )
        }

        printi("Sent \(sigName) to pid \(process.pid) – \(process.commandLine)")
    }

    /// Kill all discovered SwiftPM processes.
    /// Returns the list of processes it inspected.
    /// If `dryRun` is true, no signals are sent; only prints what it would kill.
    @discardableResult
    public func killAll(
        force: Bool = false,
        dryRun: Bool = false,
        cwd overrideCWD: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let procs = try await list(cwd: overrideCWD)
        if procs.isEmpty {
            printi("No SwiftPM processes detected.")
            return []
        }

        let sigName = force ? "SIGKILL" : "SIGTERM"
        if dryRun {
            printi("Dry run: found \(procs.count) SwiftPM processes. Would send \(sigName) to:")
        } else {
            printi("Found \(procs.count) SwiftPM processes. Sending \(sigName)…")
        }

        for p in procs {
            do {
                try kill(p, force: force, dryRun: dryRun)
            } catch {
                printi("Failed to kill pid \(p.pid): \(error)")
            }
        }

        return procs
    }

    private static func isSwiftPMCommandLine(_ cmd: String) -> Bool {
        guard !cmd.isEmpty else { return false }

        let tokens = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let firstToken = tokens.first else { return false }

        let binaryName = String(firstToken.split(separator: "/").last ?? firstToken)

        guard binaryName == "swift" || binaryName.hasPrefix("swift-") else {
            return false
        }

        if binaryName == "swift" {
            if tokens.count >= 2 {
                let sub = tokens[1].lowercased()
                let pmSubcommands: Set<String> = ["build", "test", "package", "run"]
                if pmSubcommands.contains(sub) {
                    return true
                }
            }
            return false
        }

        if binaryName.hasPrefix("swift-") {
            return true
        }

        return false
    }
}
