import Foundation
import Primitives

/// A size as written in package.frame: `"2G"`, `"500M"`, `"1.5G"`, `"4096"`. Units are binary
/// (K = 1024) and case-insensitive; a trailing `B`/`iB` is allowed (`"2GB"`, `"2GiB"`).
public struct ByteCount: CodableInvariant, Sendable, Hashable, Comparable {
    public enum Error: Swift.Error, Sendable, Equatable, LocalizedError {
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .invalid(let raw): return "'\(raw)' is not a size; write it like \"2G\", \"500M\" or \"1.5G\"."
            }
        }
    }

    public let raw: String
    public let bytes: Int64

    public init(_ raw: String) throws(Error) {
        var text = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if text.hasSuffix("IB") { text.removeLast(2) } else if text.hasSuffix("B"), text.count > 1, text.dropLast().last?.isLetter == true { text.removeLast() }
        let units: [Character: Double] = ["K": 1_024, "M": 1_048_576, "G": 1_073_741_824, "T": 1_099_511_627_776]
        var multiplier: Double = 1
        if let last = text.last, let unit = units[last] {
            multiplier = unit
            text.removeLast()
        }
        guard let value = Double(text), value >= 0, value.isFinite, value * multiplier < Double(Int64.max) else {
            throw .invalid(raw)
        }
        self.raw = raw
        self.bytes = Int64(value * multiplier)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.bytes < rhs.bytes
    }
}

/// `.wipe = .{ .above = "2G" }` in package.frame: after a successful build, test or bench run
/// in that package, wipe its caches when they exceed `above` (the keep list still applies).
public struct WipePolicy: Codable, Sendable, Equatable {
    public let above: ByteCount

    public init(above: ByteCount) {
        self.above = above
    }
}
