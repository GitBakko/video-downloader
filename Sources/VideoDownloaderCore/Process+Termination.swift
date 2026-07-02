import Foundation

/// A one-shot async signal that bridges `Process.terminationHandler` — a callback
/// that fires exactly once on a background queue — to `async`/`await`, so callers
/// can wait for a child process to exit WITHOUT blocking a cooperative thread with
/// `Process.waitUntilExit()`.
///
/// Wire it up BEFORE `Process.run()` so the callback can never be missed:
///
///     let terminated = ProcessTerminationSignal()
///     process.terminationHandler = { _ in terminated.signal() }
///     try process.run()
///     // …read pipes…
///     await terminated.wait()   // returns once the child has terminated
final class ProcessTerminationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var continuation: CheckedContinuation<Void, Never>?

    /// Called from `terminationHandler`. Resumes a pending `wait()` (if any) or
    /// records that termination happened so a later `wait()` returns immediately.
    func signal() {
        lock.lock()
        isSignaled = true
        let waiter = continuation
        continuation = nil
        lock.unlock()
        waiter?.resume()
    }

    /// Suspends until `signal()` has been (or is) called. Never blocks a thread.
    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if isSignaled {
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }
}
