import Foundation
import Version

extension BuildObjectConfiguration {
    public func string() -> String {
        let typesBlock = PklText.collection(
            "types", values: types.map(\.rawValue).sorted()
        )

        let pklContent = """
        uuid = \(PklText.quote(uuid.uuidString))
        name = \(PklText.quote(name))
        \(typesBlock)
        versions {
            release {
                major = \(versions.release.major)
                minor = \(versions.release.minor)
                patch = \(versions.release.patch)
            }
        }
        compile {
        \(compile.contents())
        }\(tests.map { "\n" + $0.contents() } ?? "")
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
