import SceneKit

// MARK: - MRI Axis

nonisolated enum MRIAxis: Int, CaseIterable, Identifiable {
    case axial, coronal, sagittal
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        }
    }
    var labelStart: String {
        switch self {
        case .axial: return "Inferior"
        case .coronal: return "Posterior"
        case .sagittal: return "Left"
        }
    }
    var labelEnd: String {
        switch self {
        case .axial: return "Superior"
        case .coronal: return "Anterior"
        case .sagittal: return "Right"
        }
    }
}

// MARK: - Shared MRI Slice Geometry

/// Camera, clip, and slice-plane geometry shared by MRI Mode and MRI Quiz.
///
/// The clip shader (see `SceneUtilities`) discards fragments by *view-space* depth, and the
/// orthographic camera always sits `cameraZ` units out along the slice axis. That's why the
/// same `clipCoord - cameraZ` mapping works for every axis — only the camera orientation and
/// the world-space plane transform change.
nonisolated enum MRISlicing {
    static let cameraZ: Float = 300
    /// SceneKit's `orthographicScale` is *half* the visible height, so the slice camera
    /// shows 180 world units (mm) across.
    static let orthographicScale: Double = 90
    /// Full-quality slice snapshot size, in pixels.
    static let snapshotSize: CGFloat = 512
    /// Snapshot pixels per world unit at `snapshotSize`. Slice classification uses this to
    /// predict how big a structure will look, so it must match the camera above.
    static let pixelsPerUnit = snapshotSize / CGFloat(2 * orthographicScale)

    /// Position + orient the orthographic camera to look down the given slice axis.
    static func orientCamera(_ cam: SCNNode, for axis: MRIAxis) {
        switch axis {
        case .axial:    // Slicing Z. Look from Superior (+Z) to Inferior (-Z).
            cam.position = SCNVector3(0, 0, cameraZ)
            cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, -1, 0), localFront: SCNVector3(0, 0, -1))
        case .coronal:  // Slicing Y. Look from Anterior (+Y) to Posterior (-Y).
            cam.position = SCNVector3(0, cameraZ, 0)
            cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        case .sagittal: // Slicing X. Look from Right (+X) to Left (-X).
            cam.position = SCNVector3(cameraZ, 0, 0)
            cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        }
    }

    /// Min/max extent along the slice axis.
    static func extent(_ bounds: MiniBrainBounds, for axis: MRIAxis) -> (min: Float, max: Float) {
        switch axis {
        case .axial:    return (bounds.minZ, bounds.maxZ)
        case .coronal:  return (bounds.minY, bounds.maxY)
        case .sagittal: return (bounds.minX, bounds.maxX)
        }
    }

    /// View-space clip depth fed to the clip shader for a world-space slice coordinate.
    static func viewClip(forCoord coord: Float) -> Float {
        coord - cameraZ
    }

    /// World-space position of the slice-plane indicator in the mini brain.
    static func planePosition(forCoord coord: Float, axis: MRIAxis) -> SCNVector3 {
        switch axis {
        case .axial:    return SCNVector3(0, 0, coord)
        case .coronal:  return SCNVector3(0, coord, 0)
        case .sagittal: return SCNVector3(coord, 0, 0)
        }
    }

    /// Orientation of the slice-plane indicator in the mini brain.
    static func planeEuler(for axis: MRIAxis) -> SCNVector3 {
        switch axis {
        case .axial:    return SCNVector3(0, 0, 0)
        case .coronal:  return SCNVector3(Float.pi / 2, 0, 0)
        case .sagittal: return SCNVector3(0, Float.pi / 2, 0)
        }
    }
}

// MARK: - Slice Renderer

/// Renders 2D slice snapshots of a clip-shaded brain scene on a private serial queue.
///
/// The slice scene is never shown in an `SCNView` — it only exists to be snapshotted — so
/// all mutation of it (camera, clip uniforms, colors) happens inside `run` on that queue,
/// and the main thread never blocks on GPU work while the user drags the slider.
nonisolated final class SliceRenderer: @unchecked Sendable {
    /// Structure nodes in the slice scene, in `LoadedBrainScene.ordered` order.
    /// Only touch these inside `run`.
    let nodes: [SCNNode]
    private let renderer: SCNRenderer
    private let camera: SCNNode
    private let queue = DispatchQueue(label: "SliceRenderer", qos: .userInitiated)
    private let lock = NSLock()
    private var latestTicket = 0

    init(scene: SCNScene, nodes: [SCNNode]) {
        self.nodes = nodes

        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = MRISlicing.orthographicScale
        cam.zNear = 1
        cam.zFar = 2000
        camera = SCNNode()
        camera.camera = cam
        MRISlicing.orientCamera(camera, for: .axial)
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
    }

    // MARK: Inside `run`

    func orient(_ axis: MRIAxis) {
        MRISlicing.orientCamera(camera, for: axis)
    }

    /// Show the slab `[coord - thickness, coord]` along the camera's axis.
    func setSlice(coord: Float, thickness: Float) {
        let viewClipZ = MRISlicing.viewClip(forCoord: coord)
        for node in nodes { node.updateClipUniforms(viewClipZ: viewClipZ, thickness: thickness) }
    }

    func snapshot(size: CGFloat = MRISlicing.snapshotSize, antialiased: Bool = true) -> UIImage {
        renderer.snapshot(
            atTime: 0,
            with: CGSize(width: size, height: size),
            antialiasingMode: antialiased ? .multisampling4X : .none
        )
    }

    // MARK: Scheduling

    /// Run `body` on the render queue. Each call gets an increasing ticket. With
    /// `dropIfSuperseded`, a request that a newer one has replaced before it starts is
    /// skipped (returns nil), so slider scrubbing never builds up a backlog of frames.
    func run<T>(dropIfSuperseded: Bool = false, _ body: @escaping @Sendable (SliceRenderer) -> T) async -> (ticket: Int, value: T)? {
        let ticket = lock.withLock { latestTicket += 1; return latestTicket }
        return await withCheckedContinuation { continuation in
            queue.async {
                if dropIfSuperseded, ticket != self.lock.withLock({ self.latestTicket }) {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (ticket, body(self)))
            }
        }
    }
}
