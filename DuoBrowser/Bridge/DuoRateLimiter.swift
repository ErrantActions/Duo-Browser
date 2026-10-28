import Foundation

struct DuoRateLimiter {
    private var timestamps: [TimeInterval] = []
    let maximumMessages: Int
    let interval: TimeInterval

    init(maximumMessages: Int = 20, interval: TimeInterval = 10) {
        self.maximumMessages = maximumMessages
        self.interval = interval
    }

    mutating func accept(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        timestamps.removeAll { $0 <= now - interval }
        guard timestamps.count < maximumMessages else { return false }
        timestamps.append(now)
        return true
    }
}
