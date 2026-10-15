import SwiftUI
import SceneKit

// MARK: - Hero Brain

/// The menu's centerpiece: the atlas brain with every gyrus outlined, glowing on black or
/// inked on paper in light mode, turning slowly. Structures answered in quizzes light up, gold
/// once mastered, so the brain doubles as a map of what you know. A sideways drag spins it.
struct HeroBrainView: View {
    /// baseName → mastery, from `ProgressStore.masteryByName`.
    let mastery: [String: ProgressStore.Mastery]
    /// False once a mode opens over the menu: the brain stops turning and SceneKit stops
    /// drawing it, right away rather than after the push finishes.
    var isActive = true

    @State private var model = HeroBrainModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HeroSceneView(scene: model.scene, orbit: model.orbit, spinning: isActive && !reduceMotion, rendering: isActive)
            .opacity(model.isLoaded ? 1 : 0)
            .scaleEffect(model.isLoaded || reduceMotion ? 1 : 0.94)
            .animation(.smooth(duration: 0.9), value: model.isLoaded)
            .task { await model.load(mastery: mastery, paper: colorScheme == .light) }
            .onChange(of: colorScheme) { model.setPaper(colorScheme == .light) }
            .onChange(of: mastery) {
                // Not while a mode is open: the brain isn't drawn then, so the change would be
                // over before anyone saw it.
                if isActive { model.apply(mastery) }
            }
            .task(id: isActive) {
                // Back on the menu after a quiz: once the mode has slid away, what you just
                // learned lights up.
                guard isActive else { return }
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled else { return }
                model.apply(mastery, duration: 1.4)
            }
            // Decorative: the progress numbers beside it say the same thing.
            .accessibilityHidden(true)
    }
}

@MainActor @Observable
final class HeroBrainModel {
    private(set) var scene = SCNScene()
    /// Carries the camera around the brain; spun by `HeroSceneView`.
    private(set) var orbit = SCNNode()
    private(set) var isLoaded = false
    /// Light mode's ink-on-paper look (`SCNNode.applyGlow`).
    private var paper = false

    private var nodes: [(node: SCNNode, baseName: String)] = []
    /// What the brain shows now.
    private var shown: [String: ProgressStore.Mastery] = [:]

    func load(mastery: [String: ProgressStore.Mastery], paper: Bool) async {
        self.paper = paper
        guard !isLoaded else { return }
        let loaded = await Background.run {
            BrainSceneLoader.load { node, s in
                node.applyGlow(SceneColors.heroGlow, fill: SceneColors.heroFill)
                // Hidden inside the opaque cortex anyway, and the two largest meshes.
                if s.name.contains("white matter") { node.isHidden = true }
            }
        }
        guard !Task.isCancelled, !loaded.structures.isEmpty else { return }

        nodes = loaded.ordered.map { ($0.node, $0.structure.baseName) }
        orbit = Self.makeCamera(in: loaded.scene, bounds: loaded.bounds)
        scene = loaded.scene
        apply(mastery, duration: 0)
        loaded.scene.rootNode.setGlowPaper(self.paper)
        isLoaded = true
    }

    func setPaper(_ paper: Bool) {
        self.paper = paper
        scene.rootNode.setGlowPaper(paper)
    }

    /// Color each structure by how well it's known, fading over `duration` seconds.
    func apply(_ mastery: [String: ProgressStore.Mastery], duration: TimeInterval = 0.6) {
        guard !nodes.isEmpty, mastery != shown else { return }
        shown = mastery
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for (node, baseName) in nodes {
            switch mastery[baseName] ?? .unseen {
            case .unseen: node.applyGlow(SceneColors.heroGlow, fill: SceneColors.heroFill)
            case .learning: node.applyGlow(SceneColors.heroLearning, fill: SceneColors.heroLearningFill)
            case .mastered: node.applyGlow(SceneColors.heroMastered, fill: SceneColors.heroMasteredFill)
            }
        }
        SCNTransaction.commit()
    }

    /// The textbook view: the left side, a little from the front and above. The camera rides
    /// on a node at the brain's center, so turning that node turns the view around the brain.
    private static func makeCamera(in scene: SCNScene, bounds: MiniBrainBounds) -> SCNNode {
        let fieldOfView: Float = 24
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(fieldOfView)
        camera.automaticallyAdjustsZRange = true

        let center = bounds.center
        let direction = simd_normalize(SIMD3<Float>(-1, 0.28, 0.32))
        let distance = bounds.maxExtent / 2 / tan(fieldOfView / 2 * .pi / 180) * 1.12

        let orbit = SCNNode()
        orbit.simdPosition = center
        scene.rootNode.addChildNode(orbit)

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "heroCamera"
        orbit.addChildNode(cameraNode)
        cameraNode.simdPosition = direction * distance
        cameraNode.simdLook(at: center, up: SIMD3(0, 0, 1), localFront: SIMD3(0, 0, -1))
        return orbit
    }
}

// MARK: - Scene View

/// Transparent SceneKit view that turns `orbit` slowly while `spinning`, and draws only while
/// `rendering`. A sideways drag turns the brain under your finger; let go and it coasts back
/// down to its slow turn, carrying on the way you flicked it.
private struct HeroSceneView: UIViewRepresentable {
    let scene: SCNScene
    let orbit: SCNNode
    let spinning: Bool
    let rendering: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = StageSCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.preferredFramesPerSecond = 30
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        configure(view, context.coordinator)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        configure(view, context.coordinator)
    }

    private func configure(_ view: SCNView, _ coordinator: Coordinator) {
        if view.scene !== scene {
            view.scene = scene
            view.pointOfView = orbit.childNodes.first { $0.camera != nil }
            view.revealWhenPrepared(scene)
        }
        coordinator.orbit = orbit
        coordinator.spinning = spinning
        if spinning {
            coordinator.resumeSpin()
        } else {
            orbit.removeAction(forKey: Coordinator.spinKey)
        }
        view.rendersContinuously = rendering && spinning
        view.isPlaying = rendering
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        static let spinKey = "spin"
        /// Seconds per turn: slow enough to read as calm, fast enough to read as alive.
        nonisolated private static let period: Float = 48
        /// How long a flick takes to settle back to the slow turn (a quarter of its pace
        /// is left after this many seconds).
        nonisolated private static let settle: Float = 0.8
        /// Fastest a flick can spin the brain, in radians per second (a turn and a half).
        private static let fastest: Float = 3 * .pi

        var orbit = SCNNode()
        var spinning = true
        /// Which way the slow turn goes: +1 to start with, then whichever way you last flicked.
        private var direction: Float = 1
        private var dragging = false
        private var startAngle: Float = 0
        /// When the finger last moved, so letting go after holding still doesn't fling.
        private var lastMove: TimeInterval = 0

        func resumeSpin() {
            guard !dragging, orbit.action(forKey: Self.spinKey) == nil else { return }
            orbit.runAction(Self.turn(direction: direction), forKey: Self.spinKey)
        }

        @objc func pan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            // Half a turn across the view's width. Dragging right swings the near side of the
            // brain right, which means the camera goes the other way.
            let radiansPerPoint = -.pi / Float(max(view.bounds.width, 1))
            switch pan.state {
            case .began:
                dragging = true
                orbit.removeAction(forKey: Self.spinKey)
                startAngle = orbit.presentation.eulerAngles.z
                // Draw every frame under the finger, even when the brain doesn't turn on its
                // own (Reduce Motion).
                (view as? SCNView)?.rendersContinuously = true
            case .changed:
                orbit.eulerAngles.z = startAngle + Float(pan.translation(in: view).x) * radiansPerPoint
                lastMove = CACurrentMediaTime()
            case .ended, .cancelled:
                dragging = false
                (view as? SCNView)?.rendersContinuously = spinning
                guard spinning else { return }
                let thrown = pan.state == .ended && CACurrentMediaTime() - lastMove < 0.1
                let speed = thrown ? Float(pan.velocity(in: view).x) * radiansPerPoint : 0
                let flick = min(max(speed, -Self.fastest), Self.fastest)
                if abs(flick) > 0.3 { direction = flick > 0 ? 1 : -1 }
                orbit.runAction(Self.coast(from: flick, direction: direction), forKey: Self.spinKey)
            default:
                break
            }
        }

        /// Only sideways drags: up and down still scroll the menu.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else { return true }
            let moved = pan.translation(in: view)
            return abs(moved.x) > abs(moved.y)
        }

        /// The slow turn, forever.
        nonisolated private static func turn(direction: Float) -> SCNAction {
            .repeatForever(.rotateBy(x: 0, y: 0, z: CGFloat(direction * 2 * .pi), duration: TimeInterval(period)))
        }

        /// Turning at `speed` (radians per second) to start with, easing exponentially to the
        /// slow turn and then carrying on with it, with no seam in the speed.
        nonisolated private static func coast(from speed: Float, direction: Float) -> SCNAction {
            let idle = direction * 2 * .pi / period
            let tau = settle / log(4)
            let duration = 5 * tau
            // Angle turned after t seconds: the slow turn plus the flick's extra, dying away.
            let angle: @Sendable (Float) -> Float = { t in idle * t + (speed - idle) * tau * (1 - exp(-t / tau)) }
            let total = angle(duration)
            guard abs(total) > 0.001 else { return turn(direction: direction) }
            let glide = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(total), duration: TimeInterval(duration))
            glide.timingFunction = { progress in angle(progress * duration) / total }
            return .sequence([glide, turn(direction: direction)])
        }
    }
}
