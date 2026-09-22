import Foundation

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
}
