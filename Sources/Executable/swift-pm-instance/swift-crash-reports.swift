import Foundation
import Path

/// One parsed macOS crash report (`.ips`) for a Swift toolchain process.
public struct SwiftCrashReport: Sendable, Hashable {
    public struct Frame: Sendable, Hashable {
        public let image: String
        public let symbol: String?
        public let imageOffset: Int?

        public init(
            image: String,
            symbol: String?,
            imageOffset: Int?
        ) {
            self.image = image
            self.symbol = symbol
            self.imageOffset = imageOffset
        }

        public var rendered: String {
            if let symbol {
                return "\(image) \(symbol)"
            }

            if let imageOffset {
                return "\(image) +\(imageOffset)"
            }

            return image
        }
    }

    public let file: URL
    public let process: String
    public let timestamp: String?
    public let exceptionType: String?
    public let signal: String?
    public let message: String?

    /// Full length of the crashed thread's stack, including frames the
    /// report elided as repeated recursion.
    public let frameCount: Int

    /// Deepest recursion the report recorded for the crashed thread, when
    /// macOS collapsed repeated frames.
    public let recursionDepth: Int?

    /// Leading frames of the crashed thread, as stored in the report.
    public let frames: [Frame]

    public init(
        file: URL,
        process: String,
        timestamp: String?,
        exceptionType: String?,
        signal: String?,
        message: String?,
        frameCount: Int,
        recursionDepth: Int?,
        frames: [Frame]
    ) {
        self.file = file
        self.process = process
        self.timestamp = timestamp
        self.exceptionType = exceptionType
        self.signal = signal
        self.message = message
        self.frameCount = frameCount
        self.recursionDepth = recursionDepth
        self.frames = frames
    }
}

public enum SwiftCrashReportError:
    Error,
    Sendable,
    LocalizedError
{
    case unreadable(
        path: String
    )

    case malformed(
        path: String,
        detail: String
    )

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "Could not read crash report at \(path)."

        case .malformed(let path, let detail):
            return "Crash report at \(path) is not in the expected .ips format: \(detail)"
        }
    }
}

/// Reads the crash reports macOS writes when a Swift toolchain process
/// (swift-package, swift-build, swift-frontend, ...) dies on a signal.
public enum SwiftCrashReports {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Logs/DiagnosticReports",
                isDirectory: true
            )
    }

    /// Most recent report files first. Returns an empty list when the
    /// directory does not exist.
    public static func list(
        in directory: URL = defaultDirectory,
        processPrefix: String = "swift",
        limit: Int = 10
    ) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let prefix = processPrefix.lowercased()
        let result = try PathScan.scan(
            PathScanSpecification(
                includes: [
                    PathExpression(
                        pattern: PathPattern(
                            .any
                        )
                    )
                ]
            ),
            relativeTo: .directoryURL(directory),
            configuration: .init(
                emitDirectories: false
            )
        )

        var dated: [(url: URL, date: Date)] = []

        for match in result.matches {
            let entry = match.url

            guard entry.pathExtension == "ips" else {
                continue
            }

            guard entry.lastPathComponent.lowercased().hasPrefix(prefix) else {
                continue
            }

            let values = try? entry.resourceValues(
                forKeys: [
                    .contentModificationDateKey
                ]
            )

            dated.append(
                (
                    url: entry,
                    date: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        dated.sort { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }

            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }

        return dated
            .prefix(max(0, limit))
            .map { $0.url }
    }

    public static func read(
        at file: URL,
        frameLimit: Int = 40
    ) throws -> SwiftCrashReport {
        guard let text = try? String(
            contentsOf: file,
            encoding: .utf8
        ) else {
            throw SwiftCrashReportError.unreadable(
                path: file.path
            )
        }

        guard let newline = text.firstIndex(of: "\n") else {
            throw SwiftCrashReportError.malformed(
                path: file.path,
                detail: "missing the header line"
            )
        }

        let header = jsonObject(
            String(text[..<newline])
        )

        guard let body = jsonObject(
            String(text[text.index(after: newline)...])
        ) else {
            throw SwiftCrashReportError.malformed(
                path: file.path,
                detail: "the body is not a JSON object"
            )
        }

        let exception = body["exception"] as? [String: Any]
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []

        let crashed = threads.first { thread in
            (thread["triggered"] as? Bool) == true
        }

        let rawFrames = crashed?["frames"] as? [[String: Any]] ?? []
        var frames: [SwiftCrashReport.Frame] = []

        for raw in rawFrames.prefix(max(0, frameLimit)) {
            var image = "<unknown>"

            if let index = raw["imageIndex"] as? Int,
               images.indices.contains(index),
               let name = images[index]["name"] as? String {
                image = name
            }

            frames.append(
                .init(
                    image: image,
                    symbol: raw["symbol"] as? String,
                    imageOffset: raw["imageOffset"] as? Int
                )
            )
        }

        let recursion = crashed?["recursionInfoArray"] as? [[String: Any]] ?? []
        let recursionDepth = recursion
            .compactMap { $0["depth"] as? Int }
            .max()

        let process =
            body["procName"] as? String
            ?? header?["app_name"] as? String
            ?? file.deletingPathExtension().lastPathComponent

        let timestamp =
            body["captureTime"] as? String
            ?? header?["timestamp"] as? String

        return SwiftCrashReport(
            file: file,
            process: process,
            timestamp: timestamp,
            exceptionType: exception?["type"] as? String,
            signal: exception?["signal"] as? String,
            message: exception?["message"] as? String,
            frameCount: crashed?["originalLength"] as? Int ?? rawFrames.count,
            recursionDepth: recursionDepth,
            frames: frames
        )
    }

    private static func jsonObject(
        _ text: String
    ) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(
            with: Data(text.utf8)
        ) else {
            return nil
        }

        return object as? [String: Any]
    }
}
