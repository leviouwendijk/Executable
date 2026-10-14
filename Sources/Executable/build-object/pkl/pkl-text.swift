import Foundation

/// Preserve the existing canonical build-object field layout while encoding Pkl strings safely.
/// The supported Pkl subset uses double-quoted strings and backslash escapes.
enum PklText {
    static func quote(_ value: String) -> String {
        String(reflecting: value)
    }
}
