import SwiftUI
import SceneKit

struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    var allowsCameraControl: Bool = true
    /// Called with every hit under the tap, nearest first.
    var onTap: (([SCNHitTestResult]) -> Void)? = nil
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
        
        // Our own double tap replaces SceneKit's built-in one (see Coordinator)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        
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
            context.coordinator.recenter(view)
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
    
    /// A glide from the current point of view back to where the camera starts out.
    private static func recenterGlide(in view: SCNView) -> CameraGlide? {
        guard let scene = view.scene, let camera = view.pointOfView else { return nil }
        let home = SCNNode()
        let frame = configureCamera(home, in: scene)
        guard let from = CameraGlide.Shot(camera, orbiting: SIMD3(view.defaultCameraController.target)),
              let to = CameraGlide.Shot(home, orbiting: SIMD3(frame.center))
        else { return nil }
        return CameraGlide(from: from, to: to)
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
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onTap: (([SCNHitTestResult]) -> Void)?
        var lastRecenter: Bool = false
        init(onTap: (([SCNHitTestResult]) -> Void)?) { self.onTap = onTap }

        func recenter(_ view: SCNView) {
            guard let camera = view.pointOfView, let glide = SceneKitView.recenterGlide(in: view) else { return }
            view.defaultCameraController.stopInertia()
            camera.runAction(glide.action, forKey: CameraGlide.actionKey)
            view.defaultCameraController.target = SCNVector3(glide.to.pivot)
        }

        /// Leave the camera wherever the glide got to, orbiting whatever is centered there,
        /// so it doesn't fight the finger.
        private func stopGlide(in view: SCNView) {
            guard let camera = view.pointOfView, camera.action(forKey: CameraGlide.actionKey) != nil else { return }
            camera.removeAction(forKey: CameraGlide.actionKey)
            let controller = view.defaultCameraController
            if let shot = CameraGlide.Shot(camera, orbiting: SIMD3(controller.target)) {
                controller.target = SCNVector3(shot.pivot)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if !hits.isEmpty {
                onTap?(hits)
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView, view.allowsCameraControl else { return }
            recenter(view)
        }

        /// The double tap sees every touch-down on the view, so it's where any touch (a drag,
        /// pinch, or tap) stops a glide in flight.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let view = gestureRecognizer.view as? SCNView { stopGlide(in: view) }
            return true
        }

        /// SceneKit's camera control has its own double tap that "switches camera" by flying
        /// the view in a straight line while turning it separately, which swings the brain
        /// off-center. Make it wait on ours, so it never fires.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            (other as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
        }
    }
}

/// Eases the camera between two shots by blending what defines them (facing, pivot, distance,
/// zoom) and placing the camera from the blend. The pivot stays centered the whole way, so the
/// brain turns in place instead of the camera sweeping past it.
nonisolated struct CameraGlide {
    /// A camera facing `orientation`, `distance` back from the `pivot` it orbits.
    struct Shot {
        var orientation: simd_quatf
        var pivot: SIMD3<Float>
        var distance: Float
        var fieldOfView: Float

        var position: SIMD3<Float> { pivot - orientation.act(SIMD3(0, 0, -1)) * distance }
    }

    static let actionKey = "cameraGlide"
    static let duration: TimeInterval = 0.6

    let from: Shot
    let to: Shot

    /// The shot at progress `t` in 0...1; the orientation turns along the shortest arc.
    func shot(at t: Float) -> Shot {
        Shot(
            orientation: simd_slerp(from.orientation, to.orientation, t),
            pivot: simd_mix(from.pivot, to.pivot, SIMD3(repeating: t)),
            distance: simd_mix(from.distance, to.distance, t),
            fieldOfView: simd_mix(from.fieldOfView, to.fieldOfView, t)
        )
    }

    var action: SCNAction {
        SCNAction.customAction(duration: Self.duration) { node, elapsed in
            let t = Float(Double(elapsed) / Self.duration)
            let shot = shot(at: t * t * (3 - 2 * t))  // smoothstep: ease in and out
            node.simdWorldOrientation = shot.orientation
            node.simdWorldPosition = shot.position
            node.camera?.fieldOfView = CGFloat(shot.fieldOfView)
        }
    }
}

extension CameraGlide.Shot {
    /// `node`'s camera as it is now, orbiting the point straight ahead that's as far away as
    /// `target` (`target` itself when the camera faces it). Nil if `node` has no camera.
    init?(_ node: SCNNode, orbiting target: SIMD3<Float>) {
        guard let camera = node.camera else { return nil }
        let distance = simd_distance(node.simdWorldPosition, target)
        self.init(
            orientation: node.simdWorldOrientation,
            pivot: node.simdWorldPosition + node.simdWorldFront * distance,
            distance: distance,
            fieldOfView: Float(camera.fieldOfView)
        )
    }
}
