import Foundation
import Network

/// The Mac's clock can drift a few seconds, which matters when Tatkal sells out in a minute or two.
/// `Clock` asks an internet time server (SNTP) how far off the Mac is and corrects every countdown.
final class Clock {
    static let shared = Clock()

    /// Seconds to add to the Mac's clock to get true time.
    private(set) var offset: TimeInterval = 0
    private(set) var lastSync: Date?
    private(set) var server = ""
    var onChange: (() -> Void)?

    var now: Date { Date().addingTimeInterval(offset) }

    private static let servers = ["time.google.com", "time.apple.com", "pool.ntp.org"]
    private static let maxOffset: TimeInterval = 600

    /// Re-syncs every 30 minutes. Call `sync()` again just before an opening for a fresh reading.
    func start() {
        sync()
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.sync() }
    }

    func sync(_ index: Int = 0) {
        guard index < Self.servers.count else { return }
        let host = Self.servers[index]
        Self.query(host) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let off = result {
                    self.offset = off
                    self.lastSync = Date()
                    self.server = host
                    self.onChange?()
                } else {
                    self.sync(index + 1)
                }
            }
        }
    }

    var summary: String {
        guard lastSync != nil else { return "Clock not synced yet (using the Mac's clock)" }
        let ms = Int((offset * 1000).rounded())
        let drift = abs(ms) < 50 ? "on time" : String(format: "%.2f s %@", abs(offset), ms > 0 ? "behind" : "ahead")
        return "Mac clock \(drift) · synced with \(server)"
    }

    /// One SNTP round trip. Returns the offset, or nil on timeout or a bad reply.
    private static func query(_ host: String, done: @escaping (TimeInterval?) -> Void) {
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 123, using: .udp)
        // One serial queue for every callback, so `finished` is only touched from one thread.
        let q = DispatchQueue(label: "clock.sntp")
        var finished = false
        let finish: (TimeInterval?) -> Void = { value in
            guard !finished else { return }
            finished = true
            conn.cancel()
            done(value)
        }
        conn.stateUpdateHandler = { state in
            if case .failed = state { finish(nil) }
        }
        conn.start(queue: q)

        var packet = [UInt8](repeating: 0, count: 48)
        packet[0] = 0x1B   // LI 0, version 3, client mode
        // A random transmit stamp the server must echo back, so a forged reply from someone else on the
        // network is rejected.
        let nonce = (0..<8).map { _ in UInt8.random(in: 0...255) }
        packet.replaceSubrange(40..<48, with: nonce)
        let t0 = Date()
        conn.send(content: Data(packet), completion: .contentProcessed { error in
            if error != nil { finish(nil) }
        })
        conn.receiveMessage { data, _, _, _ in
            let t3 = Date()
            guard let data, data.count >= 48 else { return finish(nil) }
            let bytes = [UInt8](data)
            // Server mode (4), not "clock unsynchronised" (LI 3), a real stratum, and our nonce echoed back.
            guard bytes[0] & 0x07 == 4, bytes[0] >> 6 != 3, (1...15).contains(bytes[1]),
                  Array(bytes[24..<32]) == nonce else { return finish(nil) }
            func stamp(_ at: Int) -> Date {
                var secs: UInt32 = 0, frac: UInt32 = 0
                for i in 0..<4 { secs = secs << 8 | UInt32(bytes[at + i]); frac = frac << 8 | UInt32(bytes[at + 4 + i]) }
                // NTP counts from 1900; Unix from 1970.
                return Date(timeIntervalSince1970: Double(secs) - 2_208_988_800 + Double(frac) / 4_294_967_296)
            }
            let t1 = stamp(32), t2 = stamp(40)
            guard t2.timeIntervalSince1970 > 1_600_000_000 else { return finish(nil) }
            let offset = (t1.timeIntervalSince(t0) + t2.timeIntervalSince(t3)) / 2
            // More than 10 minutes out is far more likely a bad reply than a Mac clock that far off,
            // so the Mac's own clock is kept instead.
            finish(abs(offset) <= maxOffset ? offset : nil)
        }
        q.asyncAfter(deadline: .now() + 3) { finish(nil) }
    }
}
