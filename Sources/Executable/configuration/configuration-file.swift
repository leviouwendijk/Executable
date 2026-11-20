import Foundation

/// Text I/O for package.frame. Decoding errors pass through unchanged; only reading and
/// writing failures are wrapped, naming the file.
enum BuildObjectFile {
    static func read<T>(
        from url: URL,
        decoding: (String) throws -> T
    ) throws -> T {
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigurationFileError.unreadable(url, error.localizedDescription)
        }
        return try decoding(source)
    }

    static func write(_ source: String, to url: URL) throws {
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigurationFileError.unwritable(url, error.localizedDescription)
        }
    }
}

public enum ConfigurationFileError: Error, Sendable, LocalizedError {
    case unreadable(URL, String)
    case unwritable(URL, String)
    case legacy(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url, let reason): return "Could not read \(url.path): \(reason)"
        case .unwritable(let url, let reason): return "Could not write \(url.path): \(reason)"
        case .legacy(let url): return "\(url.path) is a legacy build-object.pkl; run `sbm modernize` to move it to package.frame."
        }
    }
}
