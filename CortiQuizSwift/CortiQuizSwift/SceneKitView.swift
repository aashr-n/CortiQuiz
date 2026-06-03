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
        let frame = Self.ensureSceneSetup(scene)
        view.pointOfView = scene.rootNode.childNode(withName: "mainCamera", recursively: false)
        view.defaultCameraController.target = frame.center
        context.coordinator.lastRecenter = recenterTrigger
        return view
    }
    
    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            let frame = Self.ensureSceneSetup(scene)
            view.pointOfView = scene.rootNode.childNode(withName: "mainCamera", recursively: false)
            view.defaultCameraController.target = frame.center
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
    @discardableResult
    private static func ensureSceneSetup(_ scene: SCNScene) -> CameraFrame {
        if let existingCamera = scene.rootNode.childNode(withName: "mainCamera", recursively: false) {
            return configureCamera(existingCamera, in: scene)
        }

        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "mainCamera"
        scene.rootNode.addChildNode(cameraNode)
        let frame = configureCamera(cameraNode, in: scene)
        
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

        return frame
    }
    
    private func recenterCamera(in view: SCNView) {
        guard let scene = view.scene,
              let camera = scene.rootNode.childNode(withName: "mainCamera", recursively: true)
        else { return }
        let frame = Self.cameraFrame(for: scene)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        Self.apply(frame, to: camera)
        SCNTransaction.commit()
        view.defaultCameraController.target = frame.center
    }

    private struct CameraFrame {
        let center: SCNVector3
        let position: SCNVector3
        let radius: Float
    }

    private struct SceneBounds {
        let minPoint: SCNVector3
        let maxPoint: SCNVector3

        var center: SCNVector3 {
            SCNVector3(
                (minPoint.x + maxPoint.x) / 2,
                (minPoint.y + maxPoint.y) / 2,
                (minPoint.z + maxPoint.z) / 2
            )
        }

        var radius: Float {
            let dx = maxPoint.x - minPoint.x
            let dy = maxPoint.y - minPoint.y
            let dz = maxPoint.z - minPoint.z
            return max(sqrt(dx * dx + dy * dy + dz * dz) / 2, 1)
        }
    }

    private static func configureCamera(_ cameraNode: SCNNode, in scene: SCNScene) -> CameraFrame {
        let frame = cameraFrame(for: scene)
        let camera = cameraNode.camera ?? SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 1
        camera.zFar = Double(max(2000, frame.radius * 8))
        cameraNode.camera = camera
        apply(frame, to: cameraNode)
        return frame
    }

    private static func apply(_ frame: CameraFrame, to cameraNode: SCNNode) {
        cameraNode.position = frame.position
        cameraNode.look(
            at: frame.center,
            up: SCNVector3(0, 0, 1),
            localFront: SCNVector3(0, 0, -1)
        )
    }

    private static func cameraFrame(for scene: SCNScene) -> CameraFrame {
        let bounds = sceneContentBounds(scene)
        let center = bounds?.center ?? SCNVector3(0, 0, 10)
        let radius = bounds?.radius ?? 110
        let viewDirection = normalized(SCNVector3(0.42, 0.84, 0.32))
        let fieldOfView = Float(30.0 * Double.pi / 180.0)
        let distance = max(radius / sin(fieldOfView / 2) * 1.18, 280)
        let position = SCNVector3(
            center.x + viewDirection.x * distance,
            center.y + viewDirection.y * distance,
            center.z + viewDirection.z * distance
        )

        return CameraFrame(center: center, position: position, radius: radius)
    }

    private static func sceneContentBounds(_ scene: SCNScene) -> SceneBounds? {
        var minPoint = SCNVector3(
            Float.greatestFiniteMagnitude,
            Float.greatestFiniteMagnitude,
            Float.greatestFiniteMagnitude
        )
        var maxPoint = SCNVector3(
            -Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude
        )
        var foundGeometry = false

        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.camera == nil, node.light == nil, node.geometry != nil else { return }
            let (localMin, localMax) = node.boundingBox
            guard localMin.x.isFinite, localMin.y.isFinite, localMin.z.isFinite,
                  localMax.x.isFinite, localMax.y.isFinite, localMax.z.isFinite,
                  localMin.x <= localMax.x, localMin.y <= localMax.y, localMin.z <= localMax.z
            else { return }

            let corners = [
                SCNVector3(localMin.x, localMin.y, localMin.z),
                SCNVector3(localMin.x, localMin.y, localMax.z),
                SCNVector3(localMin.x, localMax.y, localMin.z),
                SCNVector3(localMin.x, localMax.y, localMax.z),
                SCNVector3(localMax.x, localMin.y, localMin.z),
                SCNVector3(localMax.x, localMin.y, localMax.z),
                SCNVector3(localMax.x, localMax.y, localMin.z),
                SCNVector3(localMax.x, localMax.y, localMax.z)
            ]

            for corner in corners {
                let point = node.convertPosition(corner, to: nil)
                minPoint.x = min(minPoint.x, point.x)
                minPoint.y = min(minPoint.y, point.y)
                minPoint.z = min(minPoint.z, point.z)
                maxPoint.x = max(maxPoint.x, point.x)
                maxPoint.y = max(maxPoint.y, point.y)
                maxPoint.z = max(maxPoint.z, point.z)
                foundGeometry = true
            }
        }

        guard foundGeometry else { return nil }
        return SceneBounds(minPoint: minPoint, maxPoint: maxPoint)
    }

    private static func normalized(_ vector: SCNVector3) -> SCNVector3 {
        let length = max(sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z), 0.0001)
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
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
