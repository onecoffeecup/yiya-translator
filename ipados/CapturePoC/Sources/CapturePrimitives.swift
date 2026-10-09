import Foundation

// This is the production PoC frame store; host checks exercise it without hardware.
// Only one value is retained. Consumers may hold one snapshot while processing.
final class LatestFrameMailbox<Value> {
    struct Frame {
        let value: Value
        let epoch: UInt64
        let index: UInt64
        let presentationSeconds: Double
        let receivedSeconds: Double
    }

    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var nextIndex: UInt64 = 0
    private var latest: Frame?

    @discardableResult
    func invalidate() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        epoch &+= 1
        nextIndex = 0
        latest = nil
        return epoch
    }

    @discardableResult
    func store(_ value: Value, epoch expected: UInt64, presentationSeconds: Double,
               receivedSeconds: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard epoch == expected else { return false }
        nextIndex &+= 1
        latest = Frame(value: value, epoch: epoch, index: nextIndex,
                       presentationSeconds: presentationSeconds, receivedSeconds: receivedSeconds)
        return true
    }

    func snapshot() -> Frame? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
}

// Serial-queue owner. Durations use systemUptime, never wall clock or stream PTS.
struct CaptureMetrics {
    private(set) var received: UInt64 = 0
    private(set) var dropped: UInt64 = 0
    private(set) var invalid: UInt64 = 0
    private(set) var fps: Double = 0
    private(set) var lastReceived: Double?
    private(set) var callbackMeanMS: Double = 0
    private(set) var callbackMaxMS: Double = 0
    private var callbackCount: UInt64 = 0
    private var windowStart: Double?
    private var windowFrames: UInt64 = 0

    mutating func receive(at now: Double) {
        received &+= 1
        lastReceived = now
        if let start = windowStart, now > start {
            windowFrames &+= 1
            if now - start >= 1 {
                fps = Double(windowFrames) / (now - start)
                windowStart = now
                windowFrames = 0
            }
        } else {
            windowStart = now
            windowFrames = 0
        }
    }

    mutating func recordCallback(seconds: Double) {
        let ms = max(0, seconds * 1_000)
        callbackCount &+= 1
        callbackMeanMS += (ms - callbackMeanMS) / Double(callbackCount)
        callbackMaxMS = max(callbackMaxMS, ms)
    }

    mutating func drop() { dropped &+= 1 }
    mutating func reject() { invalid &+= 1 }
    func age(at now: Double) -> Double? { lastReceived.map { max(0, now - $0) } }
    func deliveredFPS(at now: Double) -> Double { (age(at: now) ?? .infinity) >= 3 ? 0 : fps }
}

struct CaptureFormatOption {
    let index: Int
    let width: Int
    let height: Int
    let minimumFPS: Double
    let maximumFPS: Double
    var pixels: Int { width * height }
    var targetFPS: Double { min(maximumFPS, max(minimumFPS, 30)) }
}

// Prefer a supported 720p/30 mode, then <=1080p near 720p; oversized modes last.
// Each frame-rate range is an option, so disjoint ranges are not flattened.
func preferredCaptureFormat(_ options: [CaptureFormatOption]) -> CaptureFormatOption? {
    options.filter {
        $0.width > 0 && $0.height > 0 && $0.minimumFPS > 0 &&
        $0.maximumFPS >= $0.minimumFPS && $0.maximumFPS.isFinite
    }.min { a, b in
        func rank(_ o: CaptureFormatOption) -> [Double] {
            [o.width <= 1920 && o.height <= 1080 ? 0 : 1,
             o.minimumFPS <= 30 && o.maximumFPS >= 30 ? 0 : 1,
             abs(Double(o.pixels - 1280 * 720)), abs(o.targetFPS - 30), Double(o.index)]
        }
        return rank(a).lexicographicallyPrecedes(rank(b))
    }
}
