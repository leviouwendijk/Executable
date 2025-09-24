import Foundation
import plate

public enum Remove {
    public static func deployedBinary(named target: String, at destinationRoot: URL) throws {
        let fm = FileManager.default
        let bin = destinationRoot.appendingPathComponent(target)
        let meta = destinationRoot.appendingPathComponent("\(target).metadata")
        var removedAny = false

        if fm.fileExists(atPath: bin.path) {
            try fm.removeItem(at: bin)
            print("Removed \(bin.path)".ansi(.brightBlack))
            removedAny = true
        }
        if fm.fileExists(atPath: meta.path) {
            try fm.removeItem(at: meta)
            print("Removed \(meta.path)".ansi(.brightBlack))
            removedAny = true
        }
        if !removedAny {
            print("Nothing to remove for '\(target)' in \(destinationRoot.path).".ansi(.yellow))
        } else {
            print("Removed deployed '\(target)'".ansi(.green))
        }
    }
}
