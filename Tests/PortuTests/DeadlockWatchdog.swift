import Dispatch
import Foundation

/// `.timeLimit` only fires at suspension points, so a thread parked inside a synchronous lock
/// hangs the whole test process until the CI job times out. The watchdog fires from a GCD
/// timer instead, which a blocked cooperative pool cannot starve, and aborts with a message
/// that names the test.
enum DeadlockWatchdog {
    /// The default sits far above a healthy run so a throttled runner never trips it; a
    /// healthy test returns first and cancels the timer.
    static func guarding<Result>(
        _ label: String,
        seconds: Int = 30,
        _ body: () async -> Result) async -> Result {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + .seconds(seconds))
        timer.setEventHandler {
            let message = "DeadlockWatchdog: \"\(label)\" still running after \(seconds)s, suspected lock deadlock; aborting the test process\n"
            FileHandle.standardError.write(Data(message.utf8))
            abort()
        }
        timer.resume()
        defer { timer.cancel() }
        return await body()
    }
}
