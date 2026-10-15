import CoreMotion
import Foundation
import LiltCore

@MainActor
final class MotionInput {
    private let manager = CMMotionManager()
    private var calibration = TiltCalibration()
    private var needsCalibration = false
    private var startedAt = 0.0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        manager.deviceMotionUpdateInterval = 1 / 120
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        // Pausing must not silently change the player's neutral holding position.
    }

    func calibrate() {
        guard let motion = freshMotion else { needsCalibration = true; return }
        calibration.calibrate(attitude: attitude(from: motion))
        needsCalibration = false
    }

    func sample(sensitivity: Double) -> Vec2 {
        guard let motion = freshMotion else { return .zero }
        if needsCalibration || !calibration.isCalibrated {
            calibration.calibrate(attitude: attitude(from: motion))
            needsCalibration = false
            return .zero
        }
        // Relative 3D attitude makes the calibrated board virtually horizontal.
        // Subtracting two raw gravity XY projections loses direction near upright.
        // Core Motion already fuses gravity and gyroscope measurements. An extra
        // display-rate low-pass filter made steering lag behind the player's hand.
        return TiltResponse.apply(calibration.projection(attitude: attitude(from: motion)), sensitivity: sensitivity)
    }

    private var freshMotion: CMDeviceMotion? {
        guard manager.isDeviceMotionActive, let motion = manager.deviceMotion,
              motion.timestamp >= startedAt else { return nil }
        return motion
    }

    private func attitude(from motion: CMDeviceMotion) -> DeviceAttitude {
        let matrix = motion.attitude.rotationMatrix
        return DeviceAttitude(rowX: SIMD3(matrix.m11, matrix.m12, matrix.m13),
            rowY: SIMD3(matrix.m21, matrix.m22, matrix.m23),
            rowZ: SIMD3(matrix.m31, matrix.m32, matrix.m33))
    }
}
