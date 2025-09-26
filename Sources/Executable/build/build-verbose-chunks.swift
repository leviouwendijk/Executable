import Foundation

@inline(__always)
public func nowMillis() -> UInt64 {
    let t = DispatchTime.now().uptimeNanoseconds
    return t / 1_000_000
}

public func countCRLF(in data: Data) -> (cr: Int, lf: Int) {
    var cr = 0, lf = 0
    for b in data { if b == 0x0D { cr += 1 } else if b == 0x0A { lf += 1 } }
    return (cr, lf)
}

public func escapedPreview(_ data: Data, limit: Int = 120) -> String {
    var s = ""
    var shown = 0
    for b in data {
        if shown >= limit { s += "…"; break }
        switch b {
        case 0x20...0x7E:
            s.append(Character(UnicodeScalar(b)))
        case 0x0A: s += "\\n"
        case 0x0D: s += "\\r"
        case 0x09: s += "\\t"
        case 0x1B: s += "\\e"   // ESC
        default:
            s += String(format: "\\x%02X", b)
        }
        shown += 1
    }
    return s
}

public func debugDumpChunk(label: String, chunk: Data) {
    let (cr, lf) = countCRLF(in: chunk)
    let ts = nowMillis()
    let meta = "[\(ts)] \(label) chunk \(chunk.count)B cr:\(cr) lf:\(lf)"
    let prev = escapedPreview(chunk)
    FileHandle.standardError.write(Data(("\(meta) | \(prev)\n").utf8))
}
