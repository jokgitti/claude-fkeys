import Foundation

/// Reads the per-session state files the Claude hook writes.
public struct StateStore: Sendable {
    public let dir: URL

    public init(dir: URL) {
        self.dir = dir
    }

    /// The daemon's own registry.json and the hook's `.tmp.<pid>` files share this
    /// directory, so only names shaped like `<uuid>.json` are read.
    static func sessionUUID(fromFilename name: String) -> String? {
        guard name.hasSuffix(".json") else { return nil }
        let stem = String(name.dropLast(5))
        guard UUID(uuidString: stem) != nil else { return nil }
        return stem
    }

    /// UUID → state. A malformed or unreadable file is skipped: one bad file
    /// must not blank the whole F-row.
    public func scan() -> [String: SessionState] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let decoder = JSONDecoder()
        var result: [String: SessionState] = [:]
        for name in names {
            guard let uuid = Self.sessionUUID(fromFilename: name) else { continue }
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let record = try? decoder.decode(SessionRecord.self, from: data)
            else { continue }
            result[uuid] = record.state
        }
        return result
    }
}
