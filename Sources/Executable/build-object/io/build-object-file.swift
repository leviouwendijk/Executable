import Foundation

/// Centralizes text I/O and keeps the Pkl representation owned by Executable.
/// Discovery uses PathAncestorSearch, which already delegates existence checks to IO.FileSystem.
/// File reads/writes retain Foundation UTF-8 and atomic-write semantics until the dedicated
/// IO text API is reviewed; do not introduce an unverified IO surface here.
enum BuildObjectFile {
    static func read<T>(
        from url: URL,
        decoding: (String) throws -> T
    ) throws -> T {
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw PklParserError.ioError("Failed to load PKL at '\(url.path)': \(error.localizedDescription)")
        }
        do {
            return try decoding(source)
        } catch let error as PklParserError {
            throw PklParserError.syntaxError("Error parsing PKL at '\(url.path)': \(error.description)")
        }
    }

    static func write(_ source: String, to url: URL) throws {
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw PklParserError.ioError("Failed to write PKL to '\(url.path)': \(error.localizedDescription)")
        }
    }
}
