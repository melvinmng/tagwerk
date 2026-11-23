import Testing

/// Yields to other tasks until `condition` holds, so a test waits for the state it asserts on instead of guessing how
/// many scheduler turns an asynchronous hand-over needs (a fixed number of yields is too short on a loaded machine).
///
/// The bound only stops a test whose condition never becomes true; it is far beyond what any hand-over needs and no
/// wall-clock time is involved. On timeout the test fails with `description` instead of a misleading follow-up
/// expectation.
@MainActor
func awaitCondition(_ description: String, maxYields: Int = 1_000_000,
                    sourceLocation: SourceLocation = #_sourceLocation, until condition: () -> Bool) async {
    var yields = 0
    while !condition() {
        guard yields < maxYields else {
            Issue.record("Timed out waiting for: \(description)", sourceLocation: sourceLocation)
            return
        }
        yields += 1
        await Task.yield()
    }
}
