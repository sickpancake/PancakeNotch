import Foundation
import Testing
@testable import Stats

private func reading(pid: pid_t = 100, footprint: UInt64 = 30_000_000, cpu: TimeInterval, uptime: TimeInterval = 1_000) -> ProcessReading {
    ProcessReading(pid: pid, footprintBytes: footprint, cpuTime: cpu, uptime: uptime)
}

@Suite("App health")
struct AppHealthTests {
    @Test func footprintOfSelfIsReadable() throws {
        let bytes = try #require(AppHealth.footprint())
        #expect(bytes > 1_000_000)
        // Same process through the other code path.
        let viaPID = try #require(AppHealth.footprint(pid: getpid()))
        #expect(viaPID > 0)
    }

    @Test func cpuTimeOfSelfIsReadable() throws {
        let first = try #require(AppHealth.cpuTime())
        // Burn a little CPU so the second reading is larger.
        var total = 0.0
        for index in 0..<2_000_000 { total += sin(Double(index)) }
        #expect(total.isFinite)
        let second = try #require(AppHealth.cpuTime())
        #expect(first > 0)
        #expect(second >= first)
        // Not raw Mach ticks: a test process hasn't used hours of CPU.
        #expect(second < 3_600)
    }

    @Test func readingOfSelfHasUptime() throws {
        let current = try #require(AppHealth.reading())
        #expect(current.pid == getpid())
        #expect(current.footprintBytes > 0)
        #expect(current.uptime > 0)
        #expect(current.uptime < 24 * 3_600)
    }

    @Test func missingProcessReadsNil() {
        // pid_t.max isn't a real process.
        #expect(AppHealth.footprint(pid: .max) == nil)
        #expect(AppHealth.cpuTime(pid: .max) == nil)
    }

    @Test func cpuPercentMath() {
        #expect(HealthSampler.cpuPercent(cpuSeconds: 1, over: 10) == 10)
        #expect(HealthSampler.cpuPercent(cpuSeconds: 6, over: 600) == 1)
        #expect(HealthSampler.cpuPercent(cpuSeconds: 2, over: 1) == 200) // two cores busy
        #expect(HealthSampler.cpuPercent(cpuSeconds: 1, over: 0) == 0)
        #expect(HealthSampler.cpuPercent(cpuSeconds: -1, over: 10) == 0)
    }

    @Test func samplesAtMostOncePerInterval() {
        var sampler = HealthSampler(interval: 600)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = sampler.sample(now: start, reading: HealthReading(app: reading(cpu: 10, uptime: 1_000), helper: nil))
        // First sample: average since launch, 10 s of CPU over 1000 s.
        #expect(first?.cpuPercent == 1)
        #expect(first?.footprintBytes == 30_000_000)
        #expect(first?.helperFootprintBytes == 0)

        #expect(sampler.sample(now: start.addingTimeInterval(300), reading: HealthReading(app: reading(cpu: 11), helper: nil)) == nil)
        #expect(!sampler.isDue(at: start.addingTimeInterval(599)))
        #expect(sampler.isDue(at: start.addingTimeInterval(600)))

        // Averages over the whole gap since the last kept sample (skipped readings don't count).
        let second = sampler.sample(now: start.addingTimeInterval(600), reading: HealthReading(app: reading(cpu: 16), helper: nil))
        #expect(second?.cpuPercent == 1) // 6 s over 600 s
        #expect(second?.date == start.addingTimeInterval(600))
    }

    @Test func helperIsAddedAndRestartsAreHandled() {
        var sampler = HealthSampler(interval: 0)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = sampler.sample(now: start, reading: HealthReading(
            app: reading(cpu: 10),
            helper: reading(pid: 200, footprint: 8_000_000, cpu: 1, uptime: 100)
        ))
        let next = sampler.sample(now: start.addingTimeInterval(10), reading: HealthReading(
            app: reading(cpu: 10.5),
            helper: reading(pid: 200, footprint: 9_000_000, cpu: 1.2, uptime: 110)
        ))
        // App 0.5 s + helper 0.2 s over 10 s.
        #expect(abs((next?.cpuPercent ?? 0) - 7) < 0.0001)
        #expect(next?.helperFootprintBytes == 9_000_000)
        #expect(next?.totalFootprintBytes == 39_000_000)

        // The helper restarted with a new pid: its share is averaged since it started.
        let restarted = sampler.sample(now: start.addingTimeInterval(20), reading: HealthReading(
            app: reading(cpu: 10.5),
            helper: reading(pid: 300, cpu: 0.5, uptime: 5)
        ))
        #expect(abs((restarted?.cpuPercent ?? 0) - 10) < 0.0001)
    }

    @Test func liveSamplerWithZeroIntervalAlwaysSamples() throws {
        var sampler = HealthSampler(interval: 0)
        let now = Date()
        let firstSample = sampler.sample(now: now, helperPID: nil)
        let first = try #require(firstSample)
        #expect(first.footprintBytes > 0)
        #expect(first.cpuPercent >= 0)
        let secondSample = sampler.sample(now: now.addingTimeInterval(1), helperPID: nil)
        let second = try #require(secondSample)
        #expect(second.cpuPercent >= 0)
    }

    @Test func clockGoingBackwardsStillSamples() {
        var sampler = HealthSampler(interval: 600)
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(sampler.sample(now: start, reading: HealthReading(app: reading(cpu: 1), helper: nil)) != nil)
        #expect(sampler.isDue(at: start.addingTimeInterval(-60)))
    }
}
