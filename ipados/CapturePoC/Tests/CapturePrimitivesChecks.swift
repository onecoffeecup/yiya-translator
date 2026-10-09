import Foundation

@main
enum CapturePrimitivesChecks {
    static func main() {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        final class Buffer { let number: Int; init(_ number: Int) { self.number = number } }
        let mailbox = LatestFrameMailbox<Buffer>()
        let epoch = mailbox.invalidate()
        weak var expired: Buffer?
        do {
            let first = Buffer(1)
            expired = first
            check(mailbox.store(first, epoch: epoch, presentationSeconds: 0, receivedSeconds: 1), "first frame")
        }
        check(expired != nil, "store retains its frame")
        mailbox.store(Buffer(2), epoch: epoch, presentationSeconds: 0.033, receivedSeconds: 1.033)
        check(expired == nil, "overwritten buffer must be released")
        check(mailbox.snapshot()?.value.number == 2 && mailbox.snapshot()?.index == 2, "latest only")
        var consumer = mailbox.snapshot()
        let nextEpoch = mailbox.invalidate()
        check(mailbox.snapshot() == nil, "stop/disconnect clears frame")
        check(consumer?.epoch == epoch && consumer?.value.number == 2, "consumer owns snapshot independently")
        check(!mailbox.store(Buffer(3), epoch: epoch, presentationSeconds: 1, receivedSeconds: 2), "late old session rejected")
        check(mailbox.snapshot() == nil, "late callback cannot repopulate slot")
        mailbox.store(Buffer(4), epoch: nextEpoch, presentationSeconds: 0, receivedSeconds: 3)
        check(mailbox.snapshot()?.index == 1, "new session counter starts at one")
        consumer = nil

        let concurrent = LatestFrameMailbox<Int>()
        let concurrentEpoch = concurrent.invalidate()
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            concurrent.store(index, epoch: concurrentEpoch, presentationSeconds: Double(index), receivedSeconds: 0)
            _ = concurrent.snapshot()
        }
        check(concurrent.snapshot()?.index == 2_000, "store/snapshot serialized under concurrent access")
        concurrent.invalidate()
        check(concurrent.snapshot() == nil, "concurrent store fully clears")

        var metrics = CaptureMetrics()
        for n in 0...30 { metrics.receive(at: Double(n) / 30) }
        check(metrics.received == 31 && abs(metrics.fps - 30) < 0.001, "count intervals, not 31 fps")
        metrics.drop(); metrics.reject()
        metrics.recordCallback(seconds: 0.002); metrics.recordCallback(seconds: 0.004)
        check(metrics.dropped == 1 && metrics.invalid == 1, "diagnostic counters")
        check(abs(metrics.callbackMeanMS - 3) < 0.001 && metrics.callbackMaxMS == 4, "callback timing")
        check(metrics.deliveredFPS(at: 4) == 0 && metrics.age(at: 4) == 3, "stall has zero delivered fps")
        metrics = CaptureMetrics()
        check(metrics.received == 0 && metrics.age(at: 10) == nil, "new session metrics reset")

        func option(_ index: Int, _ w: Int, _ h: Int, _ min: Double, _ max: Double) -> CaptureFormatOption {
            CaptureFormatOption(index: index, width: w, height: h, minimumFPS: min, maximumFPS: max)
        }
        check(preferredCaptureFormat([option(0, 3840, 2160, 30, 60), option(1, 1280, 720, 24, 30),
                                      option(2, 1920, 1080, 24, 60)])?.index == 1, "prefer 720p30")
        check(preferredCaptureFormat([option(0, 1280, 720, 60, 60), option(0, 1280, 720, 24, 24)])?.targetFPS == 24,
              "disjoint ranges must not invent unsupported 30fps")
        check(preferredCaptureFormat([option(0, 0, 720, 1, 30), option(1, 1280, 720, 60, 30)]) == nil,
              "invalid formats rejected")
        print("CapturePrimitivesChecks: passed (bounded ownership, epochs, concurrent access, FPS, timing, supported formats)")
    }
}
