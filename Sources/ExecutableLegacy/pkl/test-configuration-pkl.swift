import Executable

/// The `tests { }` section of a build-object.pkl.
extension TestConfiguration {
    public func contents() -> String {
        var lines = ["tests {"]
        if let primary { lines.append("    primary = \(PklText.quote(primary))") }
        if !groups.isEmpty {
            lines.append("    groups {")
            for name in groups.keys.sorted() {
                lines.append(PklText.collection(name, values: groups[name] ?? [], indent: 2))
            }
            lines.append("    }")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
