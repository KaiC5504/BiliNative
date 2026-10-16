import Foundation
import BiliShared

public enum RangeRequest: Equatable, Sendable {
    case full
    case range(ByteRange)
    case unsatisfiable

    /// Single ranges only: "a-b", "a-" and the suffix form "-n". An end past the file is clamped.
    public static func parse(_ header: String?, totalSize: Int64) -> RangeRequest {
        guard let header = header?.trimmingCharacters(in: .whitespaces).lowercased(), !header.isEmpty else { return .full }
        guard header.hasPrefix("bytes="), totalSize > 0 else { return .unsatisfiable }
        let spec = header.dropFirst(6)
        guard !spec.contains(",") else { return .unsatisfiable }
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return .unsatisfiable }
        let start: Int64
        let end: Int64
        if parts[0].isEmpty {
            guard let suffix = Int64(parts[1]), suffix > 0 else { return .unsatisfiable }
            start = max(0, totalSize - suffix)
            end = totalSize - 1
        } else {
            guard let first = Int64(parts[0]) else { return .unsatisfiable }
            start = first
            if parts[1].isEmpty {
                end = totalSize - 1
            } else {
                guard let last = Int64(parts[1]) else { return .unsatisfiable }
                end = min(last, totalSize - 1)
            }
        }
        guard start < totalSize, let range = ByteRange(start: start, end: end) else { return .unsatisfiable }
        return .range(range)
    }
}
