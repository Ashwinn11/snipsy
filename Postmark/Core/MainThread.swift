import SwiftUI
import QuartzCore

/// Suspends until the current runloop turn — and the CoreAnimation commit it
/// carries — has finished, plus one more turn so the committed frame is the
/// animation baseline. Choreography that awaits this cannot race an expensive
/// first frame: a `withAnimation` issued afterwards animates from what is
/// actually on screen instead of finishing wall-clock during the stall and
/// landing as a single-frame snap.
@MainActor
func afterNextCommit() async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            DispatchQueue.main.async { c.resume() }
        }
    }
}

#if DEBUG
/// Frame-hitch logger for simulator audits: writes display-link gaps > 90 ms
/// and labeled timeline marks to Documents/hitches.txt so recordings can be
/// correlated with what the main thread was doing.
@MainActor
final class HitchMonitor {
    static let shared = HitchMonitor()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var lines: [String] = []
    private let t0 = CACurrentMediaTime()

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        if last > 0, now - last > 0.09 {
            append(String(format: "HITCH %8.3f gap=%.0fms", now - t0, (now - last) * 1000))
        }
        last = now
    }

    func mark(_ label: String) {
        append(String(format: "MARK  %8.3f %@", CACurrentMediaTime() - t0, label))
    }

    private func append(_ line: String) {
        lines.append(line)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? lines.joined(separator: "\n")
            .write(to: docs.appendingPathComponent("hitches.txt"),
                   atomically: true, encoding: .utf8)
    }
}

@MainActor func dbgMark(_ label: String) { HitchMonitor.shared.mark(label) }
#else
@MainActor func dbgMark(_ label: String) {}
#endif
