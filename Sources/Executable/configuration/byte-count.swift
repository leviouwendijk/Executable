import Foundation

/// A size in package.frame, in binary units (K = 1024): `.gigabytes(2.5)`, `.megabytes(500)`.
/// Frame reads a call as a one-field object, so `.gigabytes(2.5)` arrives as
/// `{ "gigabytes": 2.5 }`; a negative or non-finite amount is rejected while decoding.
public enum ByteCount: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    case kilobytes(Double)
    case megabytes(Double)
    case gigabytes(Double)
    case terabytes(Double)

    public var bytes: Int64 {
        let (amount, unit) = parts
        return Int64(amount * unit)
    }

    /// 2.5G, 500M: the short form sbm prints.
    public var description: String {
        let (amount, _) = parts
        let number = amount == amount.rounded() ? String(Int64(amount)) : String(amount)
        switch self {
        case .kilobytes: return number + "K"
        case .megabytes: return number + "M"
        case .gigabytes: return number + "G"
        case .terabytes: return number + "T"
        }
    }

    var parts: (amount: Double, unit: Double) {
        switch self {
        case .kilobytes(let amount): return (amount, 1_024)
        case .megabytes(let amount): return (amount, 1_048_576)
        case .gigabytes(let amount): return (amount, 1_073_741_824)
        case .terabytes(let amount): return (amount, 1_099_511_627_776)
        }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kilobytes, megabytes, gigabytes, terabytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let present = CodingKeys.allCases.filter(container.contains)
        guard present.count == 1, let key = present.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A size is one of .kilobytes(n), .megabytes(n), .gigabytes(n), .terabytes(n)."
            ))
        }
        let amount = try container.decode(Double.self, forKey: key)
        guard amount >= 0, amount.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A size can't be negative.")
        }
        switch key {
        case .kilobytes: self = .kilobytes(amount)
        case .megabytes: self = .megabytes(amount)
        case .gigabytes: self = .gigabytes(amount)
        case .terabytes: self = .terabytes(amount)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let (amount, _) = parts
        switch self {
        case .kilobytes: try container.encode(amount, forKey: .kilobytes)
        case .megabytes: try container.encode(amount, forKey: .megabytes)
        case .gigabytes: try container.encode(amount, forKey: .gigabytes)
        case .terabytes: try container.encode(amount, forKey: .terabytes)
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.bytes < rhs.bytes
    }
}

/// `.wipe = .{ .above = .gigabytes(2) }` in package.frame: after a successful build, test or
/// bench run in that package, wipe its caches when they exceed `above` (the keep list applies).
public struct WipePolicy: Codable, Sendable, Equatable {
    public let above: ByteCount

    public init(above: ByteCount) {
        self.above = above
    }
}
