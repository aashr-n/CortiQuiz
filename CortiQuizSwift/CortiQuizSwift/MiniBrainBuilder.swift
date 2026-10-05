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
}

nonisolated struct MiniBrainResult {
    let scene: SCNScene
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

        // Slice plane
        let planeSize = bounds.maxExtent * 0.8
        let plane = SCNPlane(width: CGFloat(planeSize), height: CGFloat(planeSize))
        let planeMat = SCNMaterial()
        planeMat.diffuse.contents = SceneColors.slicePlane
        planeMat.isDoubleSided = true
        planeMat.blendMode = .alpha
        plane.materials = [planeMat]
        let planeNode = SCNNode(geometry: plane)
        planeNode.name = "slicePlane"
        scene.rootNode.addChildNode(planeNode)

        // Camera
        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.zNear = 1
        cam.zFar = 2000
        let camNode = SCNNode()
        camNode.camera = cam
        // Oblique view for mini brain
        camNode.position = SCNVector3(200, 200, 100)
        camNode.look(at: SCNVector3(0, 0, (bounds.minZ + bounds.maxZ)/2), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
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
}
