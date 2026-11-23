import Darwin
import Testing

@testable import MatrixIntegration

struct OpenFileLimitTests {
  /// Darwin's `RLIM_INFINITY`, which isn't imported into Swift.
  let unlimited = rlim_t(Int64.max)

  @Test func raisesToTarget() {
    #expect(OpenFileLimit.raisedSoftLimit(current: 256, hard: unlimited, target: 4096) == 4096)
  }

  @Test func stopsAtHardLimit() {
    #expect(OpenFileLimit.raisedSoftLimit(current: 256, hard: 1024, target: 4096) == 1024)
  }

  @Test func neverLowers() {
    #expect(OpenFileLimit.raisedSoftLimit(current: 8192, hard: unlimited, target: 4096) == nil)
    #expect(OpenFileLimit.raisedSoftLimit(current: 1024, hard: 1024, target: 4096) == nil)
  }

  @Test func raiseAppliesToProcess() {
    OpenFileLimit.raise()

    var limit = rlimit()
    #expect(getrlimit(RLIMIT_NOFILE, &limit) == 0)
    #expect(limit.rlim_cur >= min(OpenFileLimit.target, limit.rlim_max))
  }
}
