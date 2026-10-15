/// Core Motion's rotation matrix maps reference-space vectors into device space.
/// Rows are copied directly from CMRotationMatrix; device +Y points toward the phone's top edge.
public struct DeviceAttitude: Sendable, Equatable {
    public var rowX: SIMD3<Double>
    public var rowY: SIMD3<Double>
    public var rowZ: SIMD3<Double>

    public init(rowX: SIMD3<Double>, rowY: SIMD3<Double>, rowZ: SIMD3<Double>) {
        self.rowX = rowX
        self.rowY = rowY
        self.rowZ = rowZ
    }

    public static let identity = DeviceAttitude(
        rowX: SIMD3(1, 0, 0), rowY: SIMD3(0, 1, 0), rowZ: SIMD3(0, 0, 1))

    public var isFinite: Bool {
        rowX.x.isFinite && rowX.y.isFinite && rowX.z.isFinite
            && rowY.x.isFinite && rowY.y.isFinite && rowY.z.isFinite
            && rowZ.x.isFinite && rowZ.y.isFinite && rowZ.z.isFinite
    }
}

/// Treats the calibrated screen plane as a virtual flat board at any comfortable holding angle.
/// Projection is unfiltered and unclamped; sensor smoothing and sensitivity belong to the input layer.
public struct TiltCalibration: Sendable {
    private var neutralNormal: SIMD3<Double>?

    public init() {}

    public var isCalibrated: Bool { neutralNormal != nil }

    /// Invalid samples preserve the last valid calibration instead of injecting nonfinite movement.
    public mutating func calibrate(attitude: DeviceAttitude) {
        guard attitude.isFinite else { return }
        neutralNormal = attitude.rowZ
    }

    public func projection(attitude: DeviceAttitude) -> Vec2 {
        guard attitude.isFinite, let neutralNormal else { return .zero }
        // D = R_current * transpose(R_neutral). Its third column maps the
        // neutral board normal into today's device axes. Virtual gravity is -D[:, 3].
        let d13 = dot(attitude.rowX, neutralNormal)
        let d23 = dot(attitude.rowY, neutralNormal)
        guard d13.isFinite, d23.isFinite else { return .zero }
        // Convert Core Motion's upward device Y into the game's downward board Y.
        return Vec2(-d13, d23)
    }

    private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
}
