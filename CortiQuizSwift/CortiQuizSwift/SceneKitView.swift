import SwiftUI
import SceneKit

struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    var allowsCameraControl: Bool = true
    var onTap: ((SCNHitTestResult) -> Void)? = nil
    var recenterTrigger: Bool = false  // Toggle to trigger recenter
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = allowsCameraControl
        
        // Constrained orbit prevents gimbal-flip (inverse spin)
        // worldUp = Z matches RAS coordinate brain orientation
        view.defaultCameraController.interactionMode = .orbitAngleMapping
        view.defaultCameraController.worldUp = SCNVector3(0, 0, 1)
        
        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            view.addGestureRecognizer(tap)
        }
        
        view.scene = scene
        Self.ensureSceneSetup(scene)
        context.coordinator.lastRecenter = recenterTrigger
        return view
    }
    
    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            Self.ensureSceneSetup(scene)
        }
        view.allowsCameraControl = allowsCameraControl
        
        // Recenter when trigger toggles
        if recenterTrigger != context.coordinator.lastRecenter {
            context.coordinator.lastRecenter = recenterTrigger
            recenterCamera(in: view)
        }
    }
    
    /// Camera facing anterior (along -Y) with superior (Z) as up.
    /// This orients the brain right-side-up for RAS coordinate models.
    private static func ensureSceneSetup(_ scene: SCNScene) {
        guard scene.rootNode.childNode(withName: "mainCamera", recursively: false) == nil else { return }
        
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 1
        camera.zFar = 2000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // Look from front-elevated (anterior = -Y in RAS) with superior (Z) as up
        cameraNode.position = SCNVector3(0, -300, 40)
        cameraNode.look(at: SCNVector3(0, 0, 10), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        cameraNode.name = "mainCamera"
        scene.rootNode.addChildNode(cameraNode)
        
        // Lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)
        
        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 800
        directional.light?.color = UIColor.white
        directional.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directional)
        
        let directional2 = SCNNode()
        directional2.light = SCNLight()
        directional2.light?.type = .directional
        directional2.light?.intensity = 400
        directional2.eulerAngles = SCNVector3(Float.pi / 4, -Float.pi / 4, 0)
        scene.rootNode.addChildNode(directional2)
    }
    
    private func recenterCamera(in view: SCNView) {
        guard let camera = view.scene?.rootNode.childNode(withName: "mainCamera", recursively: true) else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        camera.position = SCNVector3(0, -300, 40)
        camera.look(at: SCNVector3(0, 0, 10), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        SCNTransaction.commit()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    class Coordinator: NSObject {
        let onTap: ((SCNHitTestResult) -> Void)?
        var lastRecenter: Bool = false
        init(onTap: ((SCNHitTestResult) -> Void)?) { self.onTap = onTap }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let hit = hits.first {
                onTap?(hit)
            }
        }
    }
}

// MARK: - Helper: Focus camera on a node

extension SCNView {
    func focusOn(node: SCNNode, duration: TimeInterval = 0.5) {
        let (bmin, bmax) = node.boundingBox
        let center = SCNVector3(
            (bmin.x + bmax.x) / 2,
            (bmin.y + bmax.y) / 2,
            (bmin.z + bmax.z) / 2
        )
        let size = Swift.max(bmax.x - bmin.x, Swift.max(bmax.y - bmin.y, bmax.z - bmin.z))
        let distance = Float(size) * 2.5
        
        if let camera = scene?.rootNode.childNode(withName: "mainCamera", recursively: true) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            camera.position = SCNVector3(center.x, center.y - distance, center.z)
            camera.look(at: center, up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.commit()
        }
    }
}
