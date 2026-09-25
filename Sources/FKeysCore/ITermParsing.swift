import Foundation

/// One entry from `it2 tab list --json`. Field order in the JSON varies
/// between objects, so this decodes by key, never by position.
public struct TabInfo: Equatable, Sendable {
    public let index: Int
    public let id: String
    public let windowID: String
    public let isActive: Bool
    public let sessionCount: Int

    public init(index: Int, id: String, windowID: String, isActive: Bool, sessionCount: Int) {
        self.index = index
        self.id = id
        self.windowID = windowID
        self.isActive = isActive
        self.sessionCount = sessionCount
    }
}

public enum ITermParsing {
    /// `it2 session list` prints one tab-separated row per session, UUID first.
    /// Anything whose first field is not a UUID is a header or an error line.
    public static func sessionUUIDs(from output: String) -> Set<String> {
        var result: Set<String> = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let first = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: first) != nil { result.insert(first) }
        }
        return result
    }

    /// `it2 tab list --json`. `nil` on anything that isn't the expected array
    /// of objects — the caller must treat that as "unknown", not "no tabs".
    public static func tabs(from json: String) -> [TabInfo]? {
        struct Raw: Decodable {
            let index: Int
            let id: String
            let window_id: String
            let is_active: Bool
            let sessions: Int
        }
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([Raw].self, from: data)
        else { return nil }
        return raw.map {
            TabInfo(index: $0.index, id: $0.id, windowID: $0.window_id, isActive: $0.is_active, sessionCount: $0.sessions)
        }
    }

    /// `it2 window list --json`: an array of `{id, ...}` objects, one per
    /// window. Only the first one's id is used — see
    /// ITermCLI.frontmostWindowTabs for why this, and not `app get-focus`,
    /// is what names "the" window.
    public static func firstWindowID(from json: String) -> String? {
        struct Raw: Decodable { let id: String }
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([Raw].self, from: data)
        else { return nil }
        return raw.first?.id
    }

    /// `it2 session get-var tab.id -s <uuid>` prints the id as a quoted
    /// string, e.g. `"2"`. `nil` for empty output (no such session).
    public static func tabID(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
