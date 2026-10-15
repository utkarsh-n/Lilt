import Foundation

/// A stateless input curve: small tilts supply useful force on the next physics step,
/// while larger angles ease toward the existing force limit. Momentum remains in the engine.
public enum TiltResponse {
    public static let smallAngleGain = 3.4
    public static let maximumComponent = 0.7
    /// About 0.026 degrees at the default sensitivity; only sensor noise is suppressed.
    public static let neutralDeadband = 0.0006

    public static func apply(_ tilt: Vec2, sensitivity: Double = 1.3) -> Vec2 {
        guard tilt.x.isFinite, tilt.y.isFinite, sensitivity.isFinite, sensitivity > 0 else { return .zero }
        let magnitude = hypot(tilt.x, tilt.y)
        guard magnitude.isFinite, magnitude > 0 else { return .zero }
        let boundedSensitivity = min(2.4, max(0.6, sensitivity))
        let activeMagnitude = max(0, magnitude * boundedSensitivity - neutralDeadband)
        let response = maximumComponent * tanh(smallAngleGain * activeMagnitude / maximumComponent)
        return (tilt / magnitude) * response
    }
}
