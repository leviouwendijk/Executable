import Foundation
import Version

extension CompiledLocalBuildObject {
    public static func nil_init() -> CompiledLocalBuildObject {
        return .init(
            version: ObjectVersion.default_version(for: .compiled),
            arguments: []
        )
    }
}
