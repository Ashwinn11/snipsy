import QuartzCore

/// Per-frame driver for shader-argument animation (shader args don't tween).
///
/// CADisplayLink rather than a TimelineView: SwiftUI's timeline `.onChange`
/// ticks can starve under load mid-animation (observed on device), freezing
/// a drive that state-based animation would have finished. A display link
/// fires on every main-loop frame; the clamped dt keeps the original
/// contract — a main-thread hitch pauses the drive, never teleports it.
@MainActor
final class DisplayLinkDriver: NSObject {

    /// Called once per frame with a clamped dt. Return false to stop.
    var onTick: ((Double) -> Bool)?

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        last = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step() {
        let now = CACurrentMediaTime()
        let dt = min(max(0, now - last), 1.0 / 15.0)
        last = now
        if onTick?(dt) != true { stop() }
    }
}
