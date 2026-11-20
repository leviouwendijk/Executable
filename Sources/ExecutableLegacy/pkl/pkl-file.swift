import Foundation

/// Text I/O for build-object.pkl and compiled.pkl; parse errors name the file.
enum PklFile {
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
