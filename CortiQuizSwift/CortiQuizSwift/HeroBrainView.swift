import SwiftUI
import SceneKit

// MARK: - Hero Brain

/// The menu's centerpiece: the atlas brain, dark with every gyrus outlined in a soft glow,
/// turning slowly. Structures answered in quizzes light up, gold once mastered, so the
/// brain doubles as a map of what you know.
struct HeroBrainView: View {
    /// baseName → mastery, from `ProgressStore.masteryByName`.
    let mastery: [String: ProgressStore.Mastery]
    /// False once a mode opens over the menu: the brain stops turning and SceneKit stops
    /// drawing it, right away rather than after the push finishes.
    var isActive = true

    @State private var model = HeroBrainModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HeroSceneView(scene: model.scene, orbit: model.orbit, spinning: isActive && !reduceMotion, rendering: isActive)
            .opacity(model.isLoaded ? 1 : 0)
            .scaleEffect(model.isLoaded || reduceMotion ? 1 : 0.94)
            .animation(.smooth(duration: 0.9), value: model.isLoaded)
            .task { await model.load(mastery: mastery) }
            .onChange(of: mastery) { model.apply(mastery) }
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

    private var nodes: [(node: SCNNode, baseName: String)] = []

    func load(mastery: [String: ProgressStore.Mastery]) async {
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
        apply(mastery, animated: false)
        isLoaded = true
    }

    /// Color each structure by how well it's known.
    func apply(_ mastery: [String: ProgressStore.Mastery], animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
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

/// Transparent, non-interactive SceneKit view that turns `orbit` slowly while `spinning`,
/// and draws only while `rendering`.
private struct HeroSceneView: UIViewRepresentable {
    let scene: SCNScene
    let orbit: SCNNode
    let spinning: Bool
    let rendering: Bool

    private static let spinKey = "spin"
    /// Seconds per turn: slow enough to read as calm, fast enough to read as alive.
    private static let period: TimeInterval = 48

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 30
        configure(view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        configure(view)
    }

    private func configure(_ view: SCNView) {
        if view.scene !== scene {
            view.scene = scene
            view.pointOfView = orbit.childNodes.first { $0.camera != nil }
            view.revealWhenPrepared(scene)
        }
        if spinning, orbit.action(forKey: Self.spinKey) == nil {
            orbit.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: 2 * .pi, duration: Self.period)),
                            forKey: Self.spinKey)
        } else if !spinning {
            orbit.removeAction(forKey: Self.spinKey)
        }
        view.rendersContinuously = rendering && spinning
        view.isPlaying = rendering
    }
}
