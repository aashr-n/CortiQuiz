import SceneKit

// MARK: - Shared Mini-Brain Builder

nonisolated struct MiniBrainBounds {
    var minX: Float = .greatestFiniteMagnitude
    var maxX: Float = -.greatestFiniteMagnitude
    var minY: Float = .greatestFiniteMagnitude
    var maxY: Float = -.greatestFiniteMagnitude
    var minZ: Float = .greatestFiniteMagnitude
    var maxZ: Float = -.greatestFiniteMagnitude

    var maxExtent: Float {
        max(maxX - minX, maxY - minY, maxZ - minZ)
    }

    var center: SIMD3<Float> {
        SIMD3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
    }
}

nonisolated struct MiniBrainResult {
    let scene: SCNScene
    /// Unit square; place it with `MRISlicing.placePlane`.
    let planeNode: SCNNode
    let nodeMap: [String: SCNNode]
}

enum MiniBrainBuilder {
    typealias Bounds = MiniBrainBounds
    typealias Result = MiniBrainResult

    /// Build a translucent gray mini-brain scene with slice plane indicator.
    /// Call from background thread — result is safe to hand to MainActor.
    nonisolated static func build(
        structures: [BrainStructure],
        bounds: Bounds
    ) -> Result {
        let scene = SCNScene()
        var nodeMap: [String: SCNNode] = [:]

        for s in structures {
            if Task.isCancelled { break }
            guard let fn = s.modelFileName,
                  let node = ModelCache.shared.node(for: fn)
            else { continue }
            node.applyColor(SceneColors.miniBrain)
            node.name = s.id
            scene.rootNode.addChildNode(node)
            nodeMap[s.id] = node
        }

        // Slice plane, drawn twice: depth-tested, so the part in front of the brain reads as
        // in front, and faintly on top of everything, so the part inside the brain stays visible.
        let planeNode = SCNNode(geometry: planeGeometry(SceneColors.slicePlane, onTop: false))
        planeNode.name = "slicePlane"
        planeNode.renderingOrder = 99
        let xRay = SCNNode(geometry: planeGeometry(SceneColors.slicePlaneXRay, onTop: true))
        xRay.renderingOrder = 100
        planeNode.addChildNode(xRay)
        scene.rootNode.addChildNode(planeNode)

        // Camera
        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.zNear = 1
        cam.zFar = 2000
        let camNode = SCNNode()
        camNode.camera = cam
        // Oblique view from front-right-above, aimed at the brain's center
        camNode.simdPosition = bounds.center + SIMD3(200, 200, 110)
        camNode.simdLook(at: bounds.center, up: SIMD3(0, 0, 1), localFront: SIMD3(0, 0, -1))
        camNode.name = "miniCamera"
        scene.rootNode.addChildNode(camNode)

        // Lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light?.type = .directional
        dir.light?.intensity = 600
        dir.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(dir)

        return Result(scene: scene, planeNode: planeNode, nodeMap: nodeMap)
    }

    nonisolated private static func planeGeometry(_ color: UIColor, onTop: Bool) -> SCNGeometry {
        let plane = SCNPlane(width: 1, height: 1)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        if onTop {
            mat.readsFromDepthBuffer = false
            mat.writesToDepthBuffer = false
        }
        plane.materials = [mat]
        return plane
    }

    /// Color one mini-brain structure, or restore its gray shell with nil. Highlights draw on
    /// top of the translucent brain so deep structures stay visible.
    static func highlight(_ node: SCNNode, color: UIColor?) {
        node.applyColor(color ?? SceneColors.miniBrain)
        drawOnTop(node, color != nil)
    }

    private static func drawOnTop(_ node: SCNNode, _ onTop: Bool) {
        node.renderingOrder = onTop ? 50 : 0
        for mat in node.geometry?.materials ?? [] {
            mat.readsFromDepthBuffer = !onTop
            mat.writesToDepthBuffer = !onTop
        }
        for child in node.childNodes { drawOnTop(child, onTop) }
    }
}
