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

    /// Patient directions at the slice image's edges, in the radiological convention: axial
    /// is seen from the feet and coronal from the front (patient's right on screen left),
    /// sagittal from the patient's left (face toward screen left). `MRISlicing.orientCamera`
    /// must agree; a unit test checks it.
    var edgeLabels: (top: String, bottom: String, left: String, right: String) {
        switch self {
        case .axial: return ("A", "P", "R", "L")
        case .coronal: return ("S", "I", "R", "L")
        case .sagittal: return ("S", "I", "A", "P")
        }
    }

    /// Scanner-style slice location ("S 12 mm") in atlas millimetres. The atlas is RAS:
    /// +X right, +Y anterior, +Z superior.
    func locationLabel(_ coord: Float) -> String {
        let mm = Int(coord.rounded())
        guard mm != 0 else { return "0 mm" }
        let (negative, positive): (String, String)
        switch self {
        case .axial: (negative, positive) = ("I", "S")
        case .coronal: (negative, positive) = ("P", "A")
        case .sagittal: (negative, positive) = ("L", "R")
        }
        return "\(mm > 0 ? positive : negative) \(abs(mm)) mm"
    }
}

// MARK: - Shared MRI Slice Geometry

/// Camera, cut, and slice-plane geometry shared by MRI Mode and MRI Quiz.
///
/// The cut shader (see `SceneUtilities`) discards fragments by *view-space* depth. The
/// orthographic camera sits `cameraDistance` units out along the slice axis, on the side
/// given by `cameraSide`, so a world coordinate `c` on that axis is at view depth
/// `side * c - cameraDistance` whatever the axis. Only the camera orientation and the
/// world-space plane transform differ per axis.
nonisolated enum MRISlicing {
    static let cameraDistance: Float = 300
    /// SceneKit's `orthographicScale` is *half* the visible height, so the slice camera shows
    /// 190 world units (mm) across: the atlas's 180 mm front-to-back plus a small margin.
    static let orthographicScale: Double = 95
    /// Reference snapshot size, in pixels: slider-drag previews, tap picking, and the scale
    /// MRI Quiz's visibility thresholds are measured in.
    static let snapshotSize: CGFloat = 512
    /// Settled frames: about a phone-width slice view at 3×, with headroom for pinch-zoom.
    static let sharpSnapshotSize: CGFloat = 1024
    /// Snapshot pixels per world unit at `snapshotSize`. Slice classification uses this to
    /// predict how big a structure will look, so it must match the camera above.
    static let pixelsPerUnit = snapshotSize / CGFloat(2 * orthographicScale)

    /// Which side of the slice axis the camera looks from (+1 or −1), chosen so the image
    /// follows `MRIAxis.edgeLabels`.
    static func cameraSide(_ axis: MRIAxis) -> Float {
        switch axis {
        case .axial: return -1    // from the feet
        case .coronal: return 1   // from the front
        case .sagittal: return -1 // from the patient's left
        }
    }

    /// Unit vector along the slice axis.
    static func axisVector(_ axis: MRIAxis) -> SIMD3<Float> {
        switch axis {
        case .axial: return SIMD3(0, 0, 1)
        case .coronal: return SIMD3(0, 1, 0)
        case .sagittal: return SIMD3(1, 0, 0)
        }
    }

    /// Position + orient the orthographic camera to look down the given slice axis, centered
    /// on `center` in the image plane.
    static func orientCamera(_ cam: SCNNode, for axis: MRIAxis, center: SIMD3<Float>) {
        let side = cameraSide(axis)
        let forward = -side * axisVector(axis)
        let up: SIMD3<Float> = axis == .axial ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
        // The camera's in-plane position is the center's; along the axis it sits at `side * cameraDistance`.
        let inPlane = center - axisVector(axis) * simd_dot(center, axisVector(axis))
        cam.simdPosition = inPlane + axisVector(axis) * (side * cameraDistance)
        // Set the basis directly: `look(at:)` can't turn the camera's default -Z view around
        // to +Z (the axial view from the feet) and leaves it looking away.
        cam.simdOrientation = simd_quatf(simd_float3x3(simd_cross(forward, up), up, -forward))
    }

    /// Min/max extent along the slice axis.
    static func extent(_ bounds: MiniBrainBounds, for axis: MRIAxis) -> (min: Float, max: Float) {
        switch axis {
        case .axial:    return (bounds.minZ, bounds.maxZ)
        case .coronal:  return (bounds.minY, bounds.maxY)
        case .sagittal: return (bounds.minX, bounds.maxX)
        }
    }

    /// View-space clip depth fed to the cut shader for a world-space slice coordinate.
    static func viewClip(forCoord coord: Float, axis: MRIAxis) -> Float {
        cameraSide(axis) * coord - cameraDistance
    }

    /// Move, turn, and size the mini brain's slice-plane indicator (a unit square) to show
    /// `coord` on `axis`, a little larger than the brain's cross-section.
    static func placePlane(_ plane: SCNNode, axis: MRIAxis, coord: Float, bounds: MiniBrainBounds) {
        let c = bounds.center
        let margin: Float = 1.2
        let sx = (bounds.maxX - bounds.minX) * margin
        let sy = (bounds.maxY - bounds.minY) * margin
        let sz = (bounds.maxZ - bounds.minZ) * margin
        switch axis {
        case .axial:
            plane.simdPosition = SIMD3(c.x, c.y, coord)
            plane.simdEulerAngles = SIMD3(0, 0, 0)
            plane.simdScale = SIMD3(sx, sy, 1)
        case .coronal:  // Local Y turns to world Z.
            plane.simdPosition = SIMD3(c.x, coord, c.z)
            plane.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            plane.simdScale = SIMD3(sx, sz, 1)
        case .sagittal: // Local X turns to world Z.
            plane.simdPosition = SIMD3(coord, c.y, c.z)
            plane.simdEulerAngles = SIMD3(0, .pi / 2, 0)
            plane.simdScale = SIMD3(sz, sy, 1)
        }
    }
}

// MARK: - Slice Renderer

/// Renders 2D slice snapshots of a brain scene, cut open and filled (see `CutFaces`), on a
/// private serial queue.
///
/// The slice scene is never shown in an `SCNView` — it only exists to be snapshotted — so
/// all mutation of it (camera, cut uniforms, colors) happens inside `run` on that queue,
/// and the main thread never blocks on GPU work while the user drags the slider.
nonisolated final class SliceRenderer: @unchecked Sendable {
    /// Structure nodes in the slice scene, in `LoadedBrainScene.ordered` order.
    /// Only touch these inside `run`.
    let nodes: [SCNNode]
    /// Each structure's own color, index-aligned with `nodes`.
    let baseColors: [UIColor]
    /// How far the background-colored outer walls are pushed back in depth. Neighboring
    /// meshes share their walls (and slightly interpenetrate after smoothing); without this a
    /// neighbor's outer wall z-fights a structure's inner wall and speckles the fill.
    static let outsideDepthPush: Float = 1

    private var colors: [UIColor]
    /// Parent of the background-colored twin of every structure node.
    private let outside = SCNNode()
    private let center: SIMD3<Float>
    private var axis: MRIAxis = .axial
    private let renderer: SCNRenderer
    private let camera: SCNNode
    private let queue = DispatchQueue(label: "SliceRenderer", qos: .userInitiated)
    private let lock = NSLock()
    private var latestTicket = 0

    /// `nodes` must be direct children of `scene.rootNode`; they're restyled with the cut
    /// shader in `colors`. `center` is the point the camera centers on.
    init(scene: SCNScene, nodes: [SCNNode], colors: [UIColor], center: SIMD3<Float> = .zero) {
        precondition(nodes.count <= 511, "structureIndex encodes at most 511 structures")
        self.nodes = nodes
        self.baseColors = colors
        self.colors = colors
        self.center = center

        for (node, color) in zip(nodes, colors) {
            let twin = ModelCache.deepClone(node)
            twin.installCutShader(color: SceneColors.sliceBackground, faces: .outside)
            outside.addChildNode(twin)
            node.installCutShader(color: color, faces: .inside)
        }
        scene.rootNode.addChildNode(outside)
        scene.background.contents = SceneColors.sliceBackground

        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = MRISlicing.orthographicScale
        cam.zNear = 1
        cam.zFar = 2000
        camera = SCNNode()
        camera.camera = cam
        scene.rootNode.addChildNode(camera)

        renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera

        orient(.axial)
        setCut(coord: center.z)
    }

    // MARK: Inside `run`

    /// Look down `axis`. Call `setCut` afterwards: the cut depends on the axis.
    func orient(_ axis: MRIAxis) {
        self.axis = axis
        MRISlicing.orientCamera(camera, for: axis, center: center)
        // Away from the camera: opposite the side it looks from.
        outside.simdPosition = MRISlicing.axisVector(axis) * (-MRISlicing.cameraSide(axis) * Self.outsideDepthPush)
    }

    /// Cut the brain at world coordinate `coord` along the current axis.
    func setCut(coord: Float) {
        let clipZ = MRISlicing.viewClip(forCoord: coord, axis: axis)
        for node in nodes { node.updateClipZ(clipZ) }
        // The twins sit `outsideDepthPush` deeper, so their cut moves with them.
        for twin in outside.childNodes { twin.updateClipZ(clipZ - Self.outsideDepthPush) }
    }

    /// Recolor the structures, index-aligned with `nodes`. Unchanged colors are skipped.
    func setColors(_ newColors: [UIColor]) {
        for i in nodes.indices where newColors[i] != colors[i] {
            nodes[i].updateDiffuseColor(newColors[i])
        }
        colors = newColors
    }

    func setColor(_ color: UIColor, at index: Int) {
        nodes[index].updateDiffuseColor(color)
        colors[index] = color
    }

    func snapshot(size: CGFloat = MRISlicing.snapshotSize, antialiased: Bool = true) -> UIImage {
        renderer.snapshot(
            atTime: 0,
            with: CGSize(width: size, height: size),
            antialiasingMode: antialiased ? .multisampling4X : .none
        )
    }

    /// Index into `nodes` of the structure cut at `point` (unit coordinates in the image,
    /// origin top-left), or nil outside every structure. Renders a frame in which each
    /// structure's flat color encodes its index, then reads one pixel.
    func structureIndex(at point: CGPoint) -> Int? {
        for (i, node) in nodes.enumerated() { node.updateDiffuseColor(Self.idColor(i)) }
        let image = snapshot(antialiased: false)
        for (node, color) in zip(nodes, colors) { node.updateDiffuseColor(color) }
        guard let rgb = image.rgb(atUnitPoint: point),
              let index = Self.index(fromID: rgb), index < nodes.count
        else { return nil }
        return index
    }

    /// Three bits per channel, each level centered in its 32-wide band so color-management
    /// rounding can't tip it into the next. Code 0 (all channels in the lowest band, like
    /// the slice background) means "no structure".
    static func idColor(_ index: Int) -> UIColor {
        let code = index + 1
        func level(_ shift: Int) -> CGFloat { CGFloat(((code >> shift) & 7) * 32 + 16) / 255 }
        return UIColor(red: level(6), green: level(3), blue: level(0), alpha: 1)
    }

    static func index(fromID rgb: (r: UInt8, g: UInt8, b: UInt8)) -> Int? {
        let code = Int(rgb.r / 32) << 6 | Int(rgb.g / 32) << 3 | Int(rgb.b / 32)
        return code == 0 ? nil : code - 1
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

// MARK: - Pixel Readback

extension UIImage {
    /// sRGB components of the pixel at `point` (unit coordinates, origin top-left).
    nonisolated func rgb(atUnitPoint point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let cg = cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let x = Int(point.x * CGFloat(cg.width)), y = Int(point.y * CGFloat(cg.height))
        guard (0..<cg.width).contains(x), (0..<cg.height).contains(y) else { return nil }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            // Bitmap contexts put y = 0 at the bottom; shift the wanted pixel onto (0, 0).
            context.draw(cg, in: CGRect(x: -x, y: y + 1 - cg.height, width: cg.width, height: cg.height))
            return true
        }
        return drawn ? (pixel[0], pixel[1], pixel[2]) : nil
    }
}
