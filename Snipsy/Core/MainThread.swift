import SwiftUI

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
