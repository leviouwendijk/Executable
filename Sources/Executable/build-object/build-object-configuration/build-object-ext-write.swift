import Foundation
import Version

extension BuildObjectConfiguration {
    public func string() -> String {
        let typesList = types
        .map(\.rawValue)
        .sorted()
        .map { "    " + PklText.quote($0) }
        .joined(separator: "\n")

        let pklContent = """
        uuid = \(PklText.quote(uuid.uuidString))
        name = \(PklText.quote(name))
        types {
        \(typesList)
        }
        versions {
            release {
                major = \(versions.release.major)
                minor = \(versions.release.minor)
                patch = \(versions.release.patch)
            }
        }
        compile {
        \(compile.contents())
        }
        details = \(PklText.quote(details))
        author = \(PklText.quote(author))
        update = \(PklText.quote(update))
        """

        return pklContent
    }

    public func write(to url: URL) throws {
        try BuildObjectFile.write(string(), to: url)
    }
}
