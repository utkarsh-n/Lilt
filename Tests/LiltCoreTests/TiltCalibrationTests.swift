import Foundation
import Testing
@testable import LiltCore

@Test func tiltCalibrationStartsQuietAndCentersEveryHoldingPose() {
    var calibration = TiltCalibration()
    #expect(!calibration.isCalibrated)
    #expect(calibration.projection(attitude: .identity) == .zero)
    for pitch in [0.0, 45, 70, 90] {
        for roll in [-25.0, 0, 25] {
            let neutral = TiltFixture.multiply(TiltFixture.x(pitch), TiltFixture.y(roll))
            calibration.calibrate(attitude: neutral)
            #expect(calibration.isCalibrated)
            let projected = calibration.projection(attitude: neutral)
            #expect(abs(projected.x) < 1e-12)
            #expect(abs(projected.y) < 1e-12)
        }
    }
}

@Test func forwardAndBackwardTenDegreeTiltsRemainSymmetricThroughUpright() {
    let expected = sin(10 * Double.pi / 180)
    for holdingPitch in [0.0, 45, 70, 90] {
        let neutral = TiltFixture.x(holdingPitch)
        var calibration = TiltCalibration()
        calibration.calibrate(attitude: neutral)
        let forward = calibration.projection(attitude: TiltFixture.multiply(TiltFixture.x(10), neutral))
        let backward = calibration.projection(attitude: TiltFixture.multiply(TiltFixture.x(-10), neutral))
        #expect(abs(forward.x) < 1e-12)
        #expect(abs(backward.x) < 1e-12)
        #expect(abs(forward.y + expected) < 1e-12, "Forward must roll toward board -Y even at \(holdingPitch) degrees")
        #expect(abs(backward.y - expected) < 1e-12)
    }
}

@Test func rightAndLeftTiltsStayStableWithArbitraryHoldingPitchAndRoll() {
    let expected = sin(10 * Double.pi / 180)
    for holdingPitch in [0.0, 45, 70, 90] {
        for holdingRoll in [-23.0, 0, 23] {
            let neutral = TiltFixture.multiply(TiltFixture.x(holdingPitch), TiltFixture.y(holdingRoll))
            var calibration = TiltCalibration()
            calibration.calibrate(attitude: neutral)
            let right = calibration.projection(attitude: TiltFixture.multiply(TiltFixture.y(-10), neutral))
            let left = calibration.projection(attitude: TiltFixture.multiply(TiltFixture.y(10), neutral))
            #expect(abs(right.x - expected) < 1e-12)
            #expect(abs(left.x + expected) < 1e-12)
            #expect(abs(right.y) < 1e-12)
            #expect(abs(left.y) < 1e-12)
        }
    }
}

@Test func aCommonReferenceYawCannotChangeCalibratedBoardInput() {
    let neutral = TiltFixture.multiply(TiltFixture.x(70), TiltFixture.y(-18))
    let relative = TiltFixture.multiply(TiltFixture.x(11), TiltFixture.y(-9))
    let current = TiltFixture.multiply(relative, neutral)
    var original = TiltCalibration()
    original.calibrate(attitude: neutral)
    let expected = original.projection(attitude: current)
    for yaw in [-170.0, -45, 0, 89, 179] {
        // A changed reference frame right-multiplies both world→device matrices.
        let referenceYaw = TiltFixture.z(yaw)
        var changedReference = TiltCalibration()
        changedReference.calibrate(attitude: TiltFixture.multiply(neutral, referenceYaw))
        let actual = changedReference.projection(attitude: TiltFixture.multiply(current, referenceYaw))
        #expect(abs(actual.x - expected.x) < 1e-12)
        #expect(abs(actual.y - expected.y) < 1e-12)
    }
}

@Test func combinedPitchRollMatchesIndependentGravityProjection() {
    let neutral = TiltFixture.multiply(TiltFixture.z(37), TiltFixture.multiply(TiltFixture.x(70), TiltFixture.y(-21)))
    // Independent trigonometric result for Rx(pitch) * Ry(-roll):
    // board X = sin(roll), board Y = -sin(pitch) * cos(roll).
    let pitch = 12.0
    let roll = 8.0
    let relative = TiltFixture.multiply(TiltFixture.x(pitch), TiltFixture.y(-roll))
    var calibration = TiltCalibration()
    calibration.calibrate(attitude: neutral)
    let actual = calibration.projection(attitude: TiltFixture.multiply(relative, neutral))
    #expect(abs(actual.x - sin(roll * Double.pi / 180)) < 1e-12)
    #expect(abs(actual.y + sin(pitch * Double.pi / 180) * cos(roll * Double.pi / 180)) < 1e-12)
}

@Test func flatCalibrationAgreesWithCoreMotionGravityAndDoesNotFilterTilt() {
    var calibration = TiltCalibration()
    calibration.calibrate(attitude: .identity)
    for degrees in [0.001, 10, 65] {
        let current = TiltFixture.multiply(TiltFixture.x(degrees), TiltFixture.y(-degrees * 0.3))
        // Core Motion's world gravity is (0, 0, -1), so device gravity is the negative third column.
        let gravityX = -current.rowX.z
        let gravityY = -current.rowY.z
        let actual = calibration.projection(attitude: current)
        #expect(abs(actual.x - gravityX) < 1e-12)
        #expect(abs(actual.y + gravityY) < 1e-12)
        #expect(actual.length > 0)
    }
}

@Test func invalidAttitudesCannotPoisonCalibrationOrProjection() {
    var calibration = TiltCalibration()
    var invalid = DeviceAttitude.identity
    invalid.rowZ.x = .nan
    calibration.calibrate(attitude: invalid)
    #expect(!calibration.isCalibrated)
    calibration.calibrate(attitude: TiltFixture.x(70))
    let validCurrent = TiltFixture.x(80)
    let before = calibration.projection(attitude: validCurrent)
    invalid.rowX.y = .infinity
    calibration.calibrate(attitude: invalid)
    #expect(calibration.isCalibrated)
    #expect(calibration.projection(attitude: validCurrent) == before)
    #expect(calibration.projection(attitude: invalid) == .zero)
    #expect(!invalid.isFinite)
}

private enum TiltFixture {
    static func x(_ degrees: Double) -> DeviceAttitude {
        let a = degrees * Double.pi / 180
        return DeviceAttitude(rowX: SIMD3(1, 0, 0), rowY: SIMD3(0, cos(a), -sin(a)), rowZ: SIMD3(0, sin(a), cos(a)))
    }

    static func y(_ degrees: Double) -> DeviceAttitude {
        let a = degrees * Double.pi / 180
        return DeviceAttitude(rowX: SIMD3(cos(a), 0, sin(a)), rowY: SIMD3(0, 1, 0), rowZ: SIMD3(-sin(a), 0, cos(a)))
    }

    static func z(_ degrees: Double) -> DeviceAttitude {
        let a = degrees * Double.pi / 180
        return DeviceAttitude(rowX: SIMD3(cos(a), -sin(a), 0), rowY: SIMD3(sin(a), cos(a), 0), rowZ: SIMD3(0, 0, 1))
    }

    static func multiply(_ a: DeviceAttitude, _ b: DeviceAttitude) -> DeviceAttitude {
        let columns = [SIMD3(b.rowX.x, b.rowY.x, b.rowZ.x),
                       SIMD3(b.rowX.y, b.rowY.y, b.rowZ.y),
                       SIMD3(b.rowX.z, b.rowY.z, b.rowZ.z)]
        func product(_ row: SIMD3<Double>) -> SIMD3<Double> {
            var output = SIMD3<Double>.zero
            for column in 0..<3 {
                for element in 0..<3 { output[column] += row[element] * columns[column][element] }
            }
            return output
        }
        return DeviceAttitude(rowX: product(a.rowX), rowY: product(a.rowY), rowZ: product(a.rowZ))
    }
}
