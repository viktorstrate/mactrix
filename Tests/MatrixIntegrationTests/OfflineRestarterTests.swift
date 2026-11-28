import Testing

@testable import MatrixIntegration

/// Drives an `OfflineRestarter` with no real waiting, recording each wait and restart.
@MainActor
final class RestarterHarness {
  var isOffline = true
  var isSavingPower = false
  var jitter = 1.0
  var waits: [Duration] = []
  var restarts = 0
  /// Called after each wait, before the restarter checks whether to restart.
  var afterWait: (RestarterHarness) -> Void = { _ in }

  lazy var restarter = OfflineRestarter(
    canRestart: { [unowned self] in isOffline },
    isSavingPower: { [unowned self] in isSavingPower },
    restart: { [unowned self] in restarts += 1 },
    sleep: { [unowned self] duration in
      waits.append(duration)
      afterWait(self)
    },
    jitter: { [unowned self] in jitter })
}

@MainActor
struct OfflineRestarterTests {
  @Test func restartsFiveTimesThenStops() async {
    let harness = RestarterHarness()
    await harness.restarter.run()

    #expect(harness.restarts == 5)
    #expect(harness.waits == [2, 4, 8, 16, 30].map { .seconds($0) })
  }

  @Test func restartsTwiceWhenSavingPower() async {
    let harness = RestarterHarness()
    harness.isSavingPower = true
    await harness.restarter.run()

    #expect(harness.restarts == 2)
    #expect(harness.waits == [5, 20].map { .seconds($0) })
  }

  @Test func savingPowerPartwayThroughCutsTheRoundShort() async {
    let harness = RestarterHarness()
    // Low Power Mode turns on during the third wait: two restarts are already as many as saving
    // power allows, so none follow it.
    harness.afterWait = { harness in
      if harness.waits.count == 3 { harness.isSavingPower = true }
    }
    await harness.restarter.run()

    #expect(harness.restarts == 2)
    #expect(harness.waits.count == 3)
  }

  @Test func savingPowerAfterOneRestartAllowsOneMore() async {
    let harness = RestarterHarness()
    harness.afterWait = { harness in
      if harness.waits.count == 1 { harness.isSavingPower = true }
    }
    await harness.restarter.run()

    // The second wait is the saving one.
    #expect(harness.restarts == 2)
    #expect(harness.waits == [.seconds(2), .seconds(20)])
  }

  @Test func stopsOnceOnline() async {
    let harness = RestarterHarness()
    harness.afterWait = { harness in
      if harness.waits.count == 2 { harness.isOffline = false }
    }
    await harness.restarter.run()

    #expect(harness.restarts == 1)
    #expect(harness.waits.count == 2)
  }

  @Test func doesNotRestartWhenItCannot() async {
    // Covers no network, a reset in progress, or a failed sign-in: `canRestart` is false.
    let harness = RestarterHarness()
    harness.isOffline = false
    await harness.restarter.run()

    #expect(harness.restarts == 0)
    #expect(harness.waits.count == 1)
  }

  @Test func waitsAreScaledByJitter() async {
    let harness = RestarterHarness()
    harness.jitter = 0.5
    await harness.restarter.run()

    #expect(harness.waits == [1, 2, 4, 8, 15].map { .seconds($0) })
  }

  @Test func startRunsOneRoundAtATimeAndAnotherAfterItEnds() async {
    let harness = RestarterHarness()
    harness.restarter.start()
    harness.restarter.start()
    while harness.restarts < 5 { await Task.yield() }
    // Let the finished round clear itself so the next start runs.
    for _ in 0..<10 { await Task.yield() }
    #expect(harness.restarts == 5)

    harness.restarter.start()
    while harness.restarts < 10 { await Task.yield() }
    #expect(harness.restarts == 10)
  }
}
