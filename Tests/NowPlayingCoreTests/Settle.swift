import Foundation

/// Waits `delay` (long enough on a normal machine), then up to 2 s more for `condition`, so slow CI
/// machines don't fail timing tests. Tests that expect nothing to change still wait the full `delay`.
@MainActor
func settle(_ delay: Duration, until condition: () -> Bool) async throws {
    try await Task.sleep(for: delay)
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}
