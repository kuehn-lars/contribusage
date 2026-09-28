import ContribusageCore
import Foundation
import Testing

/// SPEC §12, §16.3: the scheduling decision as a pure function.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let minute: TimeInterval = 60

/// The Claude Code probe row of SPEC §12.
private let probe = SchedulePolicy(
    defaultInterval: .seconds(15 * 60), minimumInterval: .seconds(5 * 60), maximumInterval: .seconds(60 * 60),
    staleAfter: .seconds(30 * 60), manualFloor: .seconds(30), needsNetwork: true)

private func next(
    _ policy: SchedulePolicy = probe, lastAttempt: Date? = now, failures: Int = 0,
    conditions: ScheduleConditions = ScheduleConditions(), manual: Bool = false
) -> Date? {
    Schedule.nextRun(
        policy: policy, lastSuccess: nil, lastAttempt: lastAttempt, failures: failures, now: now,
        conditions: conditions, manual: manual)
}

@Test func aSourceThatNeverRanIsDueNow() {
    #expect(next(lastAttempt: nil) == now)
}

@Test func theDefaultIntervalFollowsTheLastRun() {
    #expect(next() == now + 15 * minute)
    #expect(
        Schedule.nextRun(
            policy: probe, lastSuccess: now - 20 * minute, lastAttempt: now - 30 * minute, failures: 0, now: now,
            conditions: ScheduleConditions()) == now - 5 * minute)
}

/// NFR-5: an interval below the minimum (a user setting) is raised to it, one above the maximum lowered.
@Test func theIntervalStaysWithinMinimumAndMaximum() {
    let tooShort = SchedulePolicy(
        defaultInterval: .seconds(60), minimumInterval: .seconds(300), maximumInterval: .seconds(3600),
        staleAfter: .seconds(1800), manualFloor: .seconds(30), needsNetwork: true)
    let tooLong = SchedulePolicy(
        defaultInterval: .seconds(7200), minimumInterval: .seconds(300), maximumInterval: .seconds(3600),
        staleAfter: .seconds(1800), manualFloor: .seconds(30), needsNetwork: true)
    #expect(next(tooShort) == now + 5 * minute)
    #expect(next(tooLong) == now + 60 * minute)
}

/// 2×, 4×, 8× the interval, capped at the maximum.
@Test(arguments: [(1, 30.0), (2, 60), (3, 60), (9, 60)])
func backoffGrowsAndIsCapped(failures: Int, minutes: Double) {
    #expect(next(failures: failures) == now + minutes * minute)
}

@Test func backoffStopsDoublingAfterEightTimes() {
    let wide = SchedulePolicy(
        defaultInterval: .seconds(60), minimumInterval: .seconds(60), maximumInterval: .seconds(86_400),
        staleAfter: .seconds(1800), manualFloor: .seconds(30), needsNetwork: false)
    #expect(next(wide, failures: 3) == now + 8 * minute)
    #expect(next(wide, failures: 4) == now + 8 * minute)
}

@Test func lowPowerModeDoublesTheInterval() {
    #expect(next(conditions: ScheduleConditions(isLowPowerMode: true)) == now + 30 * minute)
}

@Test func offlineSkipsOnlySourcesThatNeedTheNetwork() {
    let offline = ScheduleConditions(isOnline: false)
    let local = SchedulePolicy(
        defaultInterval: .seconds(900), minimumInterval: .seconds(300), maximumInterval: .seconds(3600),
        staleAfter: .seconds(1800), manualFloor: .seconds(30), needsNetwork: false)
    #expect(next(conditions: offline) == nil)
    #expect(next(conditions: offline, manual: true) == nil)
    #expect(next(local, conditions: offline) == now + 15 * minute)
}

@Test func nothingRunsWhileAsleepAndWakeWaitsTenSeconds() {
    #expect(next(lastAttempt: nil, conditions: ScheduleConditions(isAsleep: true)) == nil)
    let woken = ScheduleConditions(lastWake: now)
    #expect(next(lastAttempt: now - 60 * minute, conditions: woken) == now + 10)
    #expect(next(conditions: woken) == now + 15 * minute)
}

/// Manual refresh ignores interval and backoff but not the floor.
@Test func manualRefreshRespectsOnlyTheFloor() {
    #expect(next(lastAttempt: now - 10, failures: 3, manual: true) == now + 20)
    #expect(next(lastAttempt: now - 20 * minute, manual: true) == now - 20 * minute + 30)
}
