import Foundation
import Version

extension BuildObjectConfiguration {
    public static func nil_init() -> BuildObjectConfiguration {
        return .init(
            name: "",
            types: [],
            versions: ProjectVersions(
                release: ObjectVersion.default_version(for: .release)    
            ),
            compile: CompileInstructionDefaults(use: false, arguments: []),
            details: "",
            author: "",
            update: ""
        )
    }
}
