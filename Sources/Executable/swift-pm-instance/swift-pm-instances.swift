import Darwin
import Foundation
import Indentation

public struct SwiftPMProcess: Sendable, Hashable {
    public let pid: pid_t
    public let commandLine: String

    public init(pid: pid_t, commandLine: String) {
        self.pid = pid
        self.commandLine = commandLine
    }
}

public enum SwiftPMProcessError: Swift.Error, LocalizedError, Sendable {
    case processSnapshotFailed(exitCode: Int32, stderr: String)
    case processSnapshotUnreadable
    case killFailed(pid: pid_t, signal: Int32, errno: Int32)
    case processesSurvived([SwiftPMProcess])

    public var errorDescription: String? {
        switch self {
        case .processSnapshotFailed(let exitCode, let stderr):
            return """
            Failed to inspect running processes.
            ps exited with \(exitCode): \(stderr)
            """

        case .processSnapshotUnreadable:
            return "Failed to decode the process snapshot returned by ps."

        case .killFailed(let pid, let signal, let errorNumber):
            return """
            kill(\(pid), \(signal)) failed with errno \(errorNumber): \
            \(String(cString: strerror(errorNumber)))
            """

        case .processesSurvived(let processes):
            let rendered = processes
                .map { "pid \($0.pid) – \($0.commandLine)" }
                .joined(separator: "\n")

            return """
            SwiftPM processes survived termination:
            \(rendered.indent())
            """
        }
    }
}

public struct SwiftPMProcesses: Sendable {
    private static let gracefulTimeoutNanoseconds: UInt64 = 1_500_000_000
    private static let forcedTimeoutNanoseconds: UInt64 = 1_000_000_000
    private static let pollingIntervalNanoseconds: UInt64 = 50_000_000

    public init() {}

    private struct ProcRow: Sendable, Hashable {
        let pid: pid_t
        let ppid: pid_t
        let command: String
    }

    public func list(
        cwd _: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let rows = try snapshot()
        let excludedPIDs = protectedProcessPIDs(in: rows)

        return rows.compactMap { row in
            guard !excludedPIDs.contains(row.pid) else {
                return nil
            }

            guard Self.isSwiftPMCommandLine(row.command) else {
                return nil
            }

            return SwiftPMProcess(
                pid: row.pid,
                commandLine: row.command
            )
        }
    }

    @discardableResult
    public func killAll(
        force: Bool = false,
        dryRun: Bool = false,
        cwd _: URL? = nil
    ) async throws -> [SwiftPMProcess] {
        let rows = try snapshot()
        let excludedPIDs = protectedProcessPIDs(in: rows)

        let matchedRoots = rows.filter { row in
            !excludedPIDs.contains(row.pid) &&
            Self.isSwiftPMCommandLine(row.command)
        }

        guard !matchedRoots.isEmpty else {
            printi("No SwiftPM processes detected.")
            return []
        }

        let processByPID = Dictionary(
            uniqueKeysWithValues: rows.map {
                ($0.pid, $0)
            }
        )

        let childrenByParent = makeChildrenByParent(from: rows)

        let orderedPIDs = orderedProcessTreePIDs(
            roots: matchedRoots.map(\.pid),
            childrenByParent: childrenByParent,
            excluding: excludedPIDs
        )

        let matchedProcesses = matchedRoots.map {
            SwiftPMProcess(
                pid: $0.pid,
                commandLine: $0.command
            )
        }

        if dryRun {
            let strategy = force
                ? "SIGKILL"
                : "SIGTERM followed automatically by SIGKILL for survivors"

            printi(
                "Found \(matchedRoots.count) SwiftPM roots. " +
                "Would terminate \(orderedPIDs.count) processes using \(strategy):"
            )

            for pid in orderedPIDs {
                let command = processByPID[pid]?.command ?? "<unknown>"
                printi("pid \(pid) – \(command)".indent())
            }

            return matchedProcesses
        }

        if force {
            printi(
                "Found \(matchedRoots.count) SwiftPM roots. " +
                "Killing \(orderedPIDs.count) processes with SIGKILL…"
            )

            try signal(
                orderedPIDs,
                signal: SIGKILL,
                signalName: "SIGKILL",
                processByPID: processByPID
            )

            _ = try await waitForTermination(
                orderedPIDs,
                timeoutNanoseconds: Self.forcedTimeoutNanoseconds
            )
        } else {
            printi(
                "Found \(matchedRoots.count) SwiftPM roots. " +
                "Terminating \(orderedPIDs.count) processes…"
            )

            try signal(
                orderedPIDs,
                signal: SIGTERM,
                signalName: "SIGTERM",
                processByPID: processByPID
            )

            let survivors = try await waitForTermination(
                orderedPIDs,
                timeoutNanoseconds: Self.gracefulTimeoutNanoseconds
            )

            if !survivors.isEmpty {
                printi(
                    "\(survivors.count) processes survived SIGTERM. " +
                    "Escalating automatically to SIGKILL…"
                )

                try signal(
                    survivors,
                    signal: SIGKILL,
                    signalName: "SIGKILL",
                    processByPID: processByPID
                )

                _ = try await waitForTermination(
                    survivors,
                    timeoutNanoseconds: Self.forcedTimeoutNanoseconds
                )
            }
        }

        let survivors = orderedPIDs
            .filter(isAlive)
            .map { pid in
                SwiftPMProcess(
                    pid: pid,
                    commandLine: processByPID[pid]?.command ?? "<unknown>"
                )
            }

        guard survivors.isEmpty else {
            throw SwiftPMProcessError.processesSurvived(survivors)
        }

        printi("Terminated all detected SwiftPM processes.")

        return matchedProcesses
    }

    private func snapshot() throws -> [ProcRow] {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "ax",
            "-o",
            "pid=,ppid=,command="
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutLock = NSLock()
        let stderrLock = NSLock()

        nonisolated(unsafe) var stdoutData = Data()
        nonisolated(unsafe) var stderrData = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                return
            }

            stdoutLock.lock()
            stdoutData.append(data)
            stdoutLock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                return
            }

            stderrLock.lock()
            stderrData.append(data)
            stderrLock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout =
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        let remainingStderr =
            stderrPipe.fileHandleForReading.readDataToEndOfFile()

        stdoutLock.lock()
        stdoutData.append(remainingStdout)
        let capturedStdout = stdoutData
        stdoutLock.unlock()

        stderrLock.lock()
        stderrData.append(remainingStderr)
        let capturedStderr = stderrData
        stderrLock.unlock()

        guard process.terminationStatus == 0 else {
            throw SwiftPMProcessError.processSnapshotFailed(
                exitCode: process.terminationStatus,
                stderr: String(
                    data: capturedStderr,
                    encoding: .utf8
                ) ?? ""
            )
        }

        guard let text = String(
            data: capturedStdout,
            encoding: .utf8
        ) else {
            throw SwiftPMProcessError.processSnapshotUnreadable
        }

        var rows: [ProcRow] = []
        rows.reserveCapacity(256)

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(
                in: .whitespaces
            )

            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(
                maxSplits: 2,
                whereSeparator: {
                    $0 == " " || $0 == "\t"
                }
            )

            guard
                parts.count == 3,
                let pidValue = Int32(parts[0]),
                let parentPIDValue = Int32(parts[1])
            else {
                continue
            }

            rows.append(
                ProcRow(
                    pid: pid_t(pidValue),
                    ppid: pid_t(parentPIDValue),
                    command: String(parts[2])
                )
            )
        }

        return rows
    }

    private func protectedProcessPIDs(
        in rows: [ProcRow]
    ) -> Set<pid_t> {
        let processByPID = Dictionary(
            uniqueKeysWithValues: rows.map {
                ($0.pid, $0)
            }
        )

        var protected = Set<pid_t>()
        var currentPID = getpid()

        while currentPID > 0 {
            guard protected.insert(currentPID).inserted else {
                break
            }

            guard let row = processByPID[currentPID] else {
                break
            }

            currentPID = row.ppid
        }

        return protected
    }

    private func makeChildrenByParent(
        from rows: [ProcRow]
    ) -> [pid_t: [pid_t]] {
        var childrenByParent: [pid_t: [pid_t]] = [:]
        childrenByParent.reserveCapacity(rows.count)

        for row in rows {
            childrenByParent[row.ppid, default: []].append(
                row.pid
            )
        }

        return childrenByParent
    }

    private func orderedProcessTreePIDs(
        roots: [pid_t],
        childrenByParent: [pid_t: [pid_t]],
        excluding excludedPIDs: Set<pid_t>
    ) -> [pid_t] {
        var visited = Set<pid_t>()
        var ordered: [pid_t] = []

        func appendTree(_ pid: pid_t) {
            guard !excludedPIDs.contains(pid) else {
                return
            }

            guard visited.insert(pid).inserted else {
                return
            }

            for child in childrenByParent[pid, default: []] {
                appendTree(child)
            }

            ordered.append(pid)
        }

        for root in roots {
            appendTree(root)
        }

        return ordered
    }

    private func waitForTermination(
        _ pids: [pid_t],
        timeoutNanoseconds: UInt64
    ) async throws -> [pid_t] {
        let start = DispatchTime.now().uptimeNanoseconds

        while true {
            try Task.checkCancellation()

            let survivors = pids.filter(isAlive)

            if survivors.isEmpty {
                return []
            }

            let elapsed =
                DispatchTime.now().uptimeNanoseconds - start

            if elapsed >= timeoutNanoseconds {
                return survivors
            }

            try await Task.sleep(
                nanoseconds: Self.pollingIntervalNanoseconds
            )
        }
    }

    private func signal(
        _ pids: [pid_t],
        signal: Int32,
        signalName: String,
        processByPID: [pid_t: ProcRow]
    ) throws {
        for pid in pids {
            guard isAlive(pid) else {
                continue
            }

            errno = 0
            let result = Darwin.kill(pid, signal)

            if result != 0 {
                let errorNumber = errno

                if errorNumber == ESRCH {
                    continue
                }

                throw SwiftPMProcessError.killFailed(
                    pid: pid,
                    signal: signal,
                    errno: errorNumber
                )
            }

            let command = processByPID[pid]?.command ?? "<unknown>"

            printi(
                "Sent \(signalName) to pid \(pid) – \(command)"
            )
        }
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        errno = 0

        if Darwin.kill(pid, 0) == 0 {
            return true
        }

        return errno != ESRCH
    }

    private static func isSwiftPMCommandLine(
        _ command: String
    ) -> Bool {
        guard !command.isEmpty else {
            return false
        }

        let tokens = command.split(
            whereSeparator: {
                $0 == " " || $0 == "\t"
            }
        )

        guard let executableToken = tokens.first else {
            return false
        }

        let executableName = String(
            executableToken
                .split(separator: "/")
                .last ?? executableToken
        )

        if executableName == "env" {
            guard tokens.count >= 3 else {
                return false
            }

            let commandName = String(
                tokens[1]
                    .split(separator: "/")
                    .last ?? tokens[1]
            )

            guard commandName == "swift" else {
                return false
            }

            return isSwiftSubcommand(tokens[2])
        }

        if executableName == "swift" {
            guard tokens.count >= 2 else {
                return false
            }

            return isSwiftSubcommand(tokens[1])
        }

        return [
            "swift-build",
            "swift-package",
            "swift-run",
            "swift-test"
        ].contains(executableName)
    }

    private static func isSwiftSubcommand(
        _ token: Substring
    ) -> Bool {
        [
            "build",
            "package",
            "run",
            "test"
        ].contains(token.lowercased())
    }
}
