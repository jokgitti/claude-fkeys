import Foundation

/// Which F-key currently points at which iTerm session UUID.
///
/// Encoded with string keys because JSONEncoder turns an [Int: String]
/// dictionary into a flat array, which is unreadable in the state file.
public struct Registry: Equatable, Sendable, Codable {
    public static let capacity = 12

    public private(set) var byKey: [Int: String]

    public init(byKey: [Int: String] = [:]) {
        self.byKey = byKey
    }

    public func key(for uuid: String) -> Int? {
        byKey.first { $0.value == uuid }?.key
    }

    public func uuid(forKey key: Int) -> String? {
        byKey[key]
    }

    /// Bind `uuid` to the lowest free key. Returns the key it already had, if any,
    /// or nil when all 12 are taken.
    @discardableResult
    public mutating func assign(_ uuid: String) -> Int? {
        if let existing = key(for: uuid) { return existing }
        guard let free = (1...Registry.capacity).first(where: { byKey[$0] == nil }) else {
            return nil
        }
        byKey[free] = uuid
        return free
    }

    public mutating func release(_ uuid: String) {
        guard let key = key(for: uuid) else { return }
        byKey.removeValue(forKey: key)
    }

    /// Drop bindings whose session no longer exists. Returns the released UUIDs, sorted.
    ///
    /// SessionEnd is not guaranteed — kill -9, a closed window and a crash all skip it —
    /// so without this, keys leak until the daemon restarts.
    @discardableResult
    public mutating func reconcile(liveUUIDs: Set<String>) -> [String] {
        let dead = byKey.filter { !liveUUIDs.contains($0.value) }
        for key in dead.keys { byKey.removeValue(forKey: key) }
        return dead.values.sorted()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: String].self)

        var decoded: [Int: String] = [:]
        var seenUUIDs: Set<String> = []
        for (rawKey, uuid) in raw {
            guard let key = Int(rawKey) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Registry key \"\(rawKey)\" is not an integer."
                )
            }
            guard (1...Registry.capacity).contains(key) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Registry key \(key) is outside 1...\(Registry.capacity)."
                )
            }
            guard decoded[key] == nil else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Registry key \(key) appears more than once."
                )
            }
            guard seenUUIDs.insert(uuid).inserted else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "UUID \"\(uuid)\" is bound to more than one key."
                )
            }
            decoded[key] = uuid
        }
        byKey = decoded
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: byKey.map { (String($0.key), $0.value) }))
    }
}
