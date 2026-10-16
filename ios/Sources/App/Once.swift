import BiliShared

/// Lets only the first of several racing callbacks through, such as the state updates that resume one continuation.
final class Once: Sendable {
    private let done = Locked(false)

    /// True for the first call only.
    func claim() -> Bool {
        done.withLock { value in
            defer { value = true }
            return !value
        }
    }
}
