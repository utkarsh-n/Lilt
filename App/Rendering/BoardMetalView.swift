import LiltCore
import MetalKit
import QuartzCore
import SwiftUI

/// A value snapshot keeps the render pass independent of observation and UI updates.
struct BoardRenderSnapshot {
    var level: MazeLevel
    var ballPosition: Vec2
    var ballRadius: Double
    var tilt: Vec2
    var fallProgress: Double
    var ghostPosition: Vec2?
    var solutionVisible: Bool
    var elapsed: Double

    init(level: MazeLevel, ballPosition: Vec2, ballRadius: Double, tilt: Vec2 = .zero,
         fallProgress: Double = 0, ghostPosition: Vec2? = nil,
         solutionVisible: Bool = false, elapsed: Double = 0) {
        self.level = level
        self.ballPosition = ballPosition
        self.ballRadius = ballRadius
        self.tilt = tilt
        self.fallProgress = fallProgress
        self.ghostPosition = ghostPosition
        self.solutionVisible = solutionVisible
        self.elapsed = elapsed
    }
}

@MainActor
protocol BoardSceneSource: AnyObject {
    func advanceFrame(timestamp: Double)
    func renderSnapshot() -> BoardRenderSnapshot
    var isRunning: Bool { get }
}

@MainActor
final class StaticBoardSource: BoardSceneSource {
    var level: MazeLevel
    var isRunning: Bool { false }
    init(level: MazeLevel) { self.level = level }
    func advanceFrame(timestamp: Double) {}
    func renderSnapshot() -> BoardRenderSnapshot {
        BoardRenderSnapshot(level: level, ballPosition: level.start, ballRadius: level.ballRadius)
    }
}

/// A native SwiftUI host for the physically lit board. Native controls live above this surface.
@MainActor
struct BoardMetalView: UIViewRepresentable {
    let source: any BoardSceneSource
    var running: Bool
    var redrawKey: Int
    var onError: (String) -> Void

    @MainActor
    final class Coordinator {
        fileprivate var renderer: BoardRenderer?
        var lastKey = Int.min
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = BoardMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.sampleCount = 1
        view.autoResizeDrawable = true
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityIdentifier = "lilt.metalBoard"
        do {
            let renderer = try BoardRenderer(view: view, source: source)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            Task { @MainActor in onError(error.localizedDescription) }
        }
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.source = source
        if let board = view as? BoardMTKView {
            board.requestedRunning = running
            board.refreshSchedule()
        }
        if context.coordinator.lastKey != redrawKey || !running {
            context.coordinator.lastKey = redrawKey
            view.setNeedsDisplay()
        }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
        view.releaseDrawables()
    }
}

@MainActor
private final class BoardMTKView: MTKView {
    var requestedRunning = false

    override init(frame frameRect: CGRect, device: (any MTLDevice)?) {
        super.init(frame: frameRect, device: device)
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification,
                     UIApplication.didBecomeActiveNotification,
                     ProcessInfo.thermalStateDidChangeNotification,
                     Notification.Name.NSProcessInfoPowerStateDidChange] {
            center.addObserver(self, selector: #selector(scheduleChanged), name: name, object: nil)
        }
    }

    required init(coder: NSCoder) { fatalError("BoardMTKView uses a programmatic initializer") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshSchedule()
        if window != nil { setNeedsDisplay() }
    }

    @objc private func scheduleChanged() {
        refreshSchedule()
        if !isPaused { setNeedsDisplay() }
    }

    func refreshSchedule() {
        let canAnimate = requestedRunning && window != nil
            && UIApplication.shared.applicationState == .active
        preferredFramesPerSecond = BoardRenderer.preferredFrameRate(window: window)
        enableSetNeedsDisplay = !canAnimate
        isPaused = !canAnimate
    }
}

/// Memory layout is shared verbatim with Board.metal. All geometry uses the physics coordinate system.
private struct BoardPrimitive {
    var a: SIMD2<Float>
    var b: SIMD2<Float>
    var metrics: SIMD4<Float> // radius, kind, stable variation, opacity
    var detail: SIMD4<Float>  // direction x/y, path offset, reserved

    init(a: Vec2, b: Vec2? = nil, radius: Double, kind: Float,
         variation: Float = 0, opacity: Float = 1, direction: Vec2 = .zero, offset: Float = 0) {
        self.a = SIMD2(Float(a.x), Float(a.y))
        let endpoint = b ?? a
        self.b = SIMD2(Float(endpoint.x), Float(endpoint.y))
        metrics = SIMD4(Float(radius), kind, variation, opacity)
        detail = SIMD4(Float(direction.x), Float(direction.y), offset, 0)
    }
}

private struct BoardUniforms {
    var viewport: SIMD4<Float> // point width / height, screen scale, time
    var board: SIMD4<Float> // level width / height, points per level unit, reserved
    var lighting: SIMD4<Float> // tilt x/y, fall progress, reduced motion
    var appearance: SIMD4<Float> // theme, high quality, reserved
}

private enum BoardRendererError: LocalizedError {
    case unavailable, shaders(String), memory
    var errorDescription: String? {
        switch self {
        case .unavailable: "This device could not create a Metal board."
        case .shaders(let detail): "The board's lighting shaders could not be loaded. \(detail)"
        case .memory: "The board's rendering memory could not be reserved."
        }
    }
}

@MainActor
private final class BoardRenderer: NSObject, MTKViewDelegate {
    private struct PipelineKey: Hashable {
        var deviceID: UInt64
        var pixelFormat: UInt
    }

    private struct PipelineResources {
        // Retain the compiled library alongside both pipelines for all preview hosts.
        var library: any MTLLibrary
        var floor: any MTLRenderPipelineState
        var objects: any MTLRenderPipelineState
    }

    // Main-actor isolation serializes initialization. Each renderer still owns its frame buffers.
    private static var pipelineCache: [PipelineKey: PipelineResources] = [:]
    private static var pipelineCacheOrder: [PipelineKey] = []
    private static let maximumPipelineCacheEntries = 4
    weak var source: (any BoardSceneSource)?
    private let queue: any MTLCommandQueue
    private let floorPipeline: any MTLRenderPipelineState
    private let objectPipeline: any MTLRenderPipelineState
    private let buffers: [any MTLBuffer]
    private let inFlight = DispatchSemaphore(value: 3)
    private var bufferIndex = 0
    private var cachedLevel: MazeLevel?
    private var cachedSolutionVisible = false
    private var staticGeometry: [BoardPrimitive] = []
    private var frameGeometry: [BoardPrimitive] = []
    private static let capacity = 4_096

    static func preferredFrameRate(window: UIWindow?) -> Int {
        let process = ProcessInfo.processInfo
        if process.isLowPowerModeEnabled || process.thermalState == .serious
            || process.thermalState == .critical { return 30 }
        let maximum = window?.windowScene?.screen.maximumFramesPerSecond ?? 60
        return min(120, maximum)
    }

    init(view: MTKView, source: any BoardSceneSource) throws {
        guard let device = view.device, let commandQueue = device.makeCommandQueue() else {
            throw BoardRendererError.unavailable
        }
        let pipelines = try Self.pipelines(device: device, pixelFormat: view.colorPixelFormat)
        self.queue = commandQueue
        self.floorPipeline = pipelines.floor
        self.objectPipeline = pipelines.objects
        var allocated: [any MTLBuffer] = []
        for index in 0..<3 {
            guard let buffer = device.makeBuffer(length: Self.capacity * MemoryLayout<BoardPrimitive>.stride,
                                                options: .storageModeShared) else {
                throw BoardRendererError.memory
            }
            buffer.label = "Lilt · retained geometry \(index)"
            allocated.append(buffer)
        }
        self.buffers = allocated
        self.source = source
        super.init()
        staticGeometry.reserveCapacity(Self.capacity)
        frameGeometry.reserveCapacity(Self.capacity)
    }

    private static func pipelines(device: any MTLDevice, pixelFormat: MTLPixelFormat) throws -> PipelineResources {
        let key = PipelineKey(deviceID: device.registryID, pixelFormat: pixelFormat.rawValue)
        if let resources = pipelineCache[key] {
            pipelineCacheOrder.removeAll { $0 == key }
            pipelineCacheOrder.append(key)
            return resources
        }
        let library = try loadLibrary(device: device)
        guard let boardVertex = library.makeFunction(name: "liltBoardVertex"),
              let boardFragment = library.makeFunction(name: "liltBoardFragment"),
              let objectVertex = library.makeFunction(name: "liltObjectVertex"),
              let objectFragment = library.makeFunction(name: "liltObjectFragment") else {
            throw BoardRendererError.shaders("One or more board entry points are missing.")
        }
        func pipeline(_ label: String, vertex: any MTLFunction, fragment: any MTLFunction) throws
            -> any MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = pixelFormat
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let resources = PipelineResources(
            library: library,
            floor: try pipeline("Lilt · handcrafted surface", vertex: boardVertex, fragment: boardFragment),
            objects: try pipeline("Lilt · analytic geometry and steel", vertex: objectVertex, fragment: objectFragment))
        if pipelineCache.count >= maximumPipelineCacheEntries, let oldest = pipelineCacheOrder.first {
            pipelineCache.removeValue(forKey: oldest)
            pipelineCacheOrder.removeFirst()
        }
        pipelineCache[key] = resources
        pipelineCacheOrder.append(key)
        return resources
    }

    private static func loadLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        let entryPoints = ["liltBoardVertex", "liltBoardFragment", "liltObjectVertex", "liltObjectFragment"]
        if let library = device.makeDefaultLibrary(),
           entryPoints.allSatisfy({ library.makeFunction(name: $0) != nil }) {
            return library
        }
        // Keep one shader source of truth. Runtime compilation also supports an Xcode
        // installation without the optional offline Metal compiler toolchain.
        guard let url = Bundle.main.url(forResource: "Board", withExtension: "metal")
                ?? Bundle.main.url(forResource: "Board", withExtension: "metal", subdirectory: "Rendering") else {
            throw BoardRendererError.shaders("Board.metal is missing from the app resources.")
        }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let options = MTLCompileOptions()
            return try device.makeLibrary(source: source, options: options)
        } catch {
            throw BoardRendererError.shaders(error.localizedDescription)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let window = view.window, !view.isHidden, view.bounds.width > 1, view.bounds.height > 1,
              UIApplication.shared.applicationState != .background, let source else { return }
        // Static previews receive a bounded, requested draw even below a scroll fold.
        // Scrolling an existing view into sight does not call didMoveToWindow again.
        // Only continuous display-link rendering skips an offscreen surface.
        if !view.isPaused {
            let intersection = view.convert(view.bounds, to: window).intersection(window.bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return }
        }
        // Never block the main thread on the GPU. Physics still advances on a skipped drawable.
        if !view.isPaused && source.isRunning { source.advanceFrame(timestamp: CACurrentMediaTime()) }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let snapshot = source.renderSnapshot()
        updateGeometry(snapshot)
        let buffer = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % buffers.count
        frameGeometry.withUnsafeBytes { data in
            if let address = data.baseAddress, !data.isEmpty {
                buffer.contents().copyMemory(from: address, byteCount: data.count)
            }
        }
        let bounds = view.bounds.size
        let levelWidth = max(snapshot.level.width, 0.01)
        let levelHeight = max(snapshot.level.height, 0.01)
        let fit = min(Double(bounds.width) / (levelWidth + 0.035),
                      Double(bounds.height) / (levelHeight + 0.035))
        let theme: Float = switch snapshot.level.theme {
        case .oak: 0
        case .jade: 1
        case .midnight: 2
        }
        var uniforms = BoardUniforms(
            viewport: SIMD4(Float(bounds.width), Float(bounds.height), Float(view.contentScaleFactor), Float(snapshot.elapsed)),
            board: SIMD4(Float(levelWidth), Float(levelHeight), Float(fit), 0),
            lighting: SIMD4(Float(snapshot.tilt.x), Float(snapshot.tilt.y), Float(snapshot.fallProgress),
                            UIAccessibility.isReduceMotionEnabled ? 1 : 0),
            appearance: SIMD4(theme, ProcessInfo.processInfo.isLowPowerModeEnabled ? 0 : 1, 0, 0))
        encoder.label = "Lilt · board frame"
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BoardUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BoardUniforms>.stride, index: 1)
        encoder.setRenderPipelineState(floorPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if !frameGeometry.isEmpty {
            encoder.setRenderPipelineState(objectPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                   instanceCount: frameGeometry.count)
        }
        encoder.endEncoding()
        command.present(drawable)
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.commit()
    }

    private func updateGeometry(_ snapshot: BoardRenderSnapshot) {
        if cachedLevel != snapshot.level || cachedSolutionVisible != snapshot.solutionVisible {
            cachedLevel = snapshot.level
            cachedSolutionVisible = snapshot.solutionVisible
            staticGeometry.removeAll(keepingCapacity: true)
            let level = snapshot.level
            if snapshot.solutionVisible {
                var distance: Float = 0
                for pair in zip(level.solution, level.solution.dropFirst()) {
                    staticGeometry.append(BoardPrimitive(a: pair.0, b: pair.1, radius: 0.003,
                                                         kind: 7, offset: distance))
                    distance += Float(pair.0.distance(to: pair.1))
                }
            }
            staticGeometry.append(BoardPrimitive(a: level.start, radius: level.ballRadius * 1.5, kind: 10))
            // Cast every wall shadow before painting any wall top, so crossings are coherent.
            for (index, wall) in level.walls.enumerated() {
                staticGeometry.append(BoardPrimitive(a: wall.a, b: wall.b, radius: wall.thickness / 2,
                                                     kind: 0, variation: Float(index)))
            }
            for hole in level.holes {
                staticGeometry.append(BoardPrimitive(a: hole.center, radius: hole.radius, kind: 2))
            }
            staticGeometry.append(BoardPrimitive(a: level.goal, radius: level.ballRadius * 1.48, kind: 3))
            for feature in level.features {
                let kind: Float = switch feature.kind {
                case .bumper: 4
                case .magnet: 5
                case .fan: 6
                }
                staticGeometry.append(BoardPrimitive(a: feature.center, radius: feature.radius,
                                                     kind: kind, direction: feature.direction))
            }
            for (index, wall) in level.walls.enumerated() {
                staticGeometry.append(BoardPrimitive(a: wall.a, b: wall.b, radius: wall.thickness / 2,
                                                     kind: 1, variation: Float(index)))
            }
            // Imported geometry has a hard upper bound; the dynamic sphere always gets its slots.
            if staticGeometry.count > Self.capacity - 2 {
                staticGeometry.removeLast(staticGeometry.count - (Self.capacity - 2))
            }
        }
        frameGeometry.removeAll(keepingCapacity: true)
        frameGeometry.append(contentsOf: staticGeometry)
        if let ghost = snapshot.ghostPosition {
            frameGeometry.append(BoardPrimitive(a: ghost, radius: snapshot.ballRadius, kind: 9, opacity: 0.35))
        }
        frameGeometry.append(BoardPrimitive(a: snapshot.ballPosition, radius: snapshot.ballRadius,
                                            kind: 8, variation: Float(snapshot.fallProgress)))
    }
}
