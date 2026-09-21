import Foundation

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle
    case working
    case waiting
}

public struct SessionRecord: Codable, Sendable, Equatable {
    public let state: SessionState
    public let ts: Int
    public let claudeSessionId: String?

    enum CodingKeys: String, CodingKey {
        case state
        case ts
        case claudeSessionId = "claude_session_id"
    }
}
