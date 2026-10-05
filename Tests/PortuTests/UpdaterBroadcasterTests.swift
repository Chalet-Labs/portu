import Foundation
@testable import Portu
import Testing

/// Pins the replay-then-live contract of `UpdaterBroadcaster` that the preference and status
/// streams rely on, independent of how the registry and per-subscriber locks are built.
///
/// Ordering is only promised for a single serial producer (production: the main-actor
/// updater controller), so the stress tests use exactly one.
struct UpdaterBroadcasterTests {
    private struct Observation: Sendable {
        let stopsEarly: Bool
        let values: [Int]
    }

    // MARK: - Replay and live delivery

    @Test(.timeLimit(.minutes(1)))
    func `new subscriber first receives the latest committed value`() async {
        let broadcaster = UpdaterBroadcaster(initialValue: 0)
        broadcaster.update(1)
        broadcaster.update(2)

        var iterator = broadcaster.stream().makeAsyncIterator()

        #expect(await iterator.next() == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func `live updates follow the replayed value in order without repeating it`() async {
        let broadcaster = UpdaterBroadcaster(initialValue: 0)
        var iterator = broadcaster.stream().makeAsyncIterator()

        broadcaster.update(1)
        broadcaster.update(2)
        broadcaster.update(3)

        var seen: [Int] = []
        while seen.count < 4, let value = await iterator.next() {
            seen.append(value)
        }
        #expect(seen == [0, 1, 2, 3])
    }

    // MARK: - Termination

    @Test(.timeLimit(.minutes(1)))
    func `a cancelled subscriber is removed and does not disturb other subscribers`() async {
        let broadcaster = UpdaterBroadcaster(initialValue: 0)
        var survivor = broadcaster.stream().makeAsyncIterator()
        do {
            var cancelled = broadcaster.stream().makeAsyncIterator()
            #expect(await cancelled.next() == 0)
            #expect(broadcaster.subscriberCount == 2)
        }
        #expect(broadcaster.subscriberCount == 1)

        broadcaster.update(1)

        #expect(await survivor.next() == 0)
        #expect(await survivor.next() == 1)
        var late = broadcaster.stream().makeAsyncIterator()
        #expect(await late.next() == 1)
    }

    // MARK: - Subscriber ordering contract

    /// The delivery lock is held across replay and catch-up, so a delivery that
    /// arrives mid-sequence queues behind it instead of overtaking the catch-up value.
    @Test(.timeLimit(.minutes(1)))
    func `a delivery arriving during replay queues behind the catch-up value`() async {
        let (deliveredEarly, stream) = await DeadlockWatchdog.guarding("delivery during replay") {
            Self.deliverDuringReplay()
        }

        #expect(deliveredEarly == false)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        #expect(await iterator.next() == 2)
        #expect(await iterator.next() == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func `catch up delivers the newer value once and nothing when the value is unchanged`() async {
        let (newerStream, newerContinuation) = AsyncStream.makeStream(of: Int.self)
        UpdaterBroadcaster<Int>.Subscriber(continuation: newerContinuation)
            .replayPrimeAndCatchUp(initial: 1) { 2 }
        newerContinuation.finish()

        let (unchangedStream, unchangedContinuation) = AsyncStream.makeStream(of: Int.self)
        UpdaterBroadcaster<Int>.Subscriber(continuation: unchangedContinuation)
            .replayPrimeAndCatchUp(initial: 5) { 5 }
        unchangedContinuation.finish()

        var newer: [Int] = []
        for await value in newerStream {
            newer.append(value)
        }
        var unchanged: [Int] = []
        for await value in unchangedStream {
            unchanged.append(value)
        }
        #expect(newer == [1, 2])
        #expect(unchanged == [5])
    }

    // MARK: - Concurrency

    /// Not gap free: a subscriber that is registered but not yet primed skips whatever
    /// the producer commits meanwhile and catches up with the latest value only.
    @Test(.timeLimit(.minutes(1)))
    func `subscribers attached mid stream see a strictly increasing sequence ending at the final value`() async {
        let updateCount = 5000
        let subscriberCount = 32
        let broadcaster = UpdaterBroadcaster(initialValue: 0)

        let observations = await DeadlockWatchdog.guarding("mid stream subscribers") {
            let producer = Task {
                for value in 1 ... updateCount {
                    broadcaster.update(value)
                    if value.isMultiple(of: 3) {
                        await Task.yield()
                    }
                }
            }

            let observations = await withTaskGroup(of: Observation.self) { group in
                for index in 0 ..< subscriberCount {
                    group.addTask {
                        // Spread attach points across the producer's run.
                        let threshold = (index + 1) * updateCount / (subscriberCount + 1)
                        while broadcaster.current() < threshold {
                            await Task.yield()
                        }
                        let stopsEarly = index.isMultiple(of: 3)
                        var seen: [Int] = []
                        for await value in broadcaster.stream() {
                            seen.append(value)
                            if value == updateCount || (stopsEarly && seen.count == 5) {
                                break
                            }
                        }
                        return Observation(stopsEarly: stopsEarly, values: seen)
                    }
                }
                var collected: [Observation] = []
                for await observation in group {
                    collected.append(observation)
                }
                return collected
            }
            await producer.value
            return observations
        }

        #expect(observations.count == subscriberCount)
        for observation in observations {
            #expect(observation.values.isEmpty == false)
            #expect(zip(observation.values, observation.values.dropFirst()).allSatisfy { $0 < $1 })
            if observation.stopsEarly == false {
                #expect(observation.values.last == updateCount)
            }
        }
        #expect(broadcaster.current() == updateCount)
    }

    /// A race detector rather than a proof: it only trips when two updates land inside
    /// the nanosecond window around a fresh subscriber's priming.
    @Test(.timeLimit(.minutes(1)))
    func `a hot serial producer never reorders what freshly attached subscribers receive`() async {
        let updateCount = 200_000
        let churnerCount = 6
        let attachesPerChurner = 600
        let broadcaster = UpdaterBroadcaster(initialValue: 0)

        let violations = await DeadlockWatchdog.guarding("hot serial producer") {
            let producer = Task {
                for value in 1 ... updateCount {
                    broadcaster.update(value)
                    if value.isMultiple(of: 512) {
                        await Task.yield()
                    }
                }
            }

            let violations = await withTaskGroup(of: Int.self) { group in
                for _ in 0 ..< churnerCount {
                    group.addTask {
                        var violations = 0
                        for _ in 0 ..< attachesPerChurner {
                            var previous = -1
                            var seenCount = 0
                            for await value in broadcaster.stream() {
                                if value <= previous {
                                    violations += 1
                                }
                                previous = value
                                seenCount += 1
                                if seenCount == 3 || value == updateCount {
                                    break
                                }
                            }
                        }
                        return violations
                    }
                }
                return await group.reduce(0, +)
            }
            await producer.value
            return violations
        }

        #expect(violations == 0)
        #expect(broadcaster.current() == updateCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func `concurrent producers subscribers and cancellations complete without deadlock`() async {
        let broadcaster = UpdaterBroadcaster(initialValue: 0)

        await DeadlockWatchdog.guarding("concurrent producers and subscribers") {
            await withTaskGroup(of: Void.self) { group in
                for producer in 0 ..< 4 {
                    group.addTask {
                        for step in 0 ..< 500 {
                            broadcaster.update(producer * 1000 + step)
                            if step.isMultiple(of: 4) {
                                await Task.yield()
                            }
                        }
                    }
                }
                for _ in 0 ..< 16 {
                    group.addTask {
                        for _ in 0 ..< 25 {
                            var iterator = broadcaster.stream().makeAsyncIterator()
                            _ = await iterator.next()
                        }
                    }
                }
            }
        }

        #expect((0 ..< 4000).contains(broadcaster.current()))
        #expect(broadcaster.subscriberCount == 0)
    }

    // MARK: - Helpers

    /// Synchronous so it may block: starts a delivery from another thread while the
    /// subscriber is inside its replay window and reports whether it got through.
    private static func deliverDuringReplay() -> (deliveredEarly: Bool, stream: AsyncStream<Int>) {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        let subscriber = UpdaterBroadcaster<Int>.Subscriber(continuation: continuation)
        // Subscriber is not Sendable; its delivery lock is what makes the concurrent call safe.
        nonisolated(unsafe) let concurrentSubscriber = subscriber
        let delivered = DispatchSemaphore(value: 0)
        var deliveredEarly = false

        subscriber.replayPrimeAndCatchUp(initial: 1) {
            Thread.detachNewThread {
                concurrentSubscriber.deliver(3)
                delivered.signal()
            }
            deliveredEarly = delivered.wait(timeout: .now() + .milliseconds(300)) == .success
            return 2
        }
        if !deliveredEarly {
            delivered.wait()
        }
        return (deliveredEarly, stream)
    }
}
