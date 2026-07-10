import CoreHaptics
import UIKit

/// Custom haptic vocabulary. Every signature moment has its own texture;
/// silently no-ops where haptics are unavailable (simulator).
@MainActor
final class Haptics {

    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    /// Shutter press: crisp, immediate.
    func shutter() {
        play([transient(0, intensity: 0.9, sharpness: 0.75)])
    }

    /// The grain dissolve: a fine fading sandpaper texture.
    func grains(duration: TimeInterval) {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.42),
                .init(parameterID: .hapticSharpness, value: 0.9),
            ],
            relativeTime: 0,
            duration: duration
        )
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.9),
                .init(relativeTime: duration * 0.6, value: 0.45),
                .init(relativeTime: duration, value: 0.0),
            ],
            relativeTime: 0
        )
        play([event], curves: [curve])
    }

    /// Postmark strike: a heavy, satisfying thunk.
    func thunk() {
        play([
            transient(0, intensity: 1.0, sharpness: 0.32),
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.5),
                    .init(parameterID: .hapticSharpness, value: 0.18),
                ],
                relativeTime: 0.012, duration: 0.14
            ),
        ])
    }

    /// Small UI confirmations.
    func tick() {
        play([transient(0, intensity: 0.42, sharpness: 0.62)])
    }

    /// Stamp landed in the collection.
    func success() {
        play([
            transient(0, intensity: 0.6, sharpness: 0.5),
            transient(0.11, intensity: 0.95, sharpness: 0.42),
        ])
    }

    private func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard let engine else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch { /* haptics are garnish, never fail loudly */ }
    }
}
