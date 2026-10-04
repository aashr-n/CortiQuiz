import SwiftUI
import SceneKit

// MARK: - MRI ViewModel

@MainActor @Observable
final class MRIViewModel {
    var slicePosition: Float = 0.5
    var isLoading = true
    var sliceImage: UIImage?
    var miniBrainScene = SCNScene()
    var recenterMini = false
    var activeAxis: MRIAxis = .axial

    private var allNodes: [SCNNode] = []
    private var bounds = MiniBrainBuilder.Bounds()
    private var setupStarted = false
    private var renderer: SCNRenderer?
    private var mriScene: SCNScene?
    private var slicePlaneNode: SCNNode?
    private var isDragging = false

    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true

        Task.detached { [weak self] in
            let loaded = BrainSceneLoader.load { node, s in
                node.installClipShader(color: UIColor(s.color))
            }
            let miniResult = MiniBrainBuilder.build(structures: loaded.structures, bounds: loaded.bounds)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = loaded.scene
                self.miniBrainScene = miniResult.scene
                self.allNodes = loaded.ordered.map { $0.node }
                self.bounds = loaded.bounds
                self.slicePlaneNode = miniResult.planeNode
                self.setupRenderer()
                self.isLoading = false
                self.updateAxis()
            }
        }
    }

    private func setupRenderer() {
        guard let scene = mriScene else { return }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 90
        camera.zNear = 1
        camera.zFar = 2000
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.name = "mriCamera"
        scene.rootNode.addChildNode(camNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let r = SCNRenderer(device: nil, options: nil)
        r.scene = scene
        r.pointOfView = camNode
        self.renderer = r
    }

    func updateAxis() {
        guard let camNode = mriScene?.rootNode.childNode(withName: "mriCamera", recursively: false) else { return }
        MRISlicing.orientCamera(camNode, for: activeAxis)
        slicePlaneNode?.eulerAngles = MRISlicing.planeEuler(for: activeAxis)
        updateSlice(highQuality: true)
    }

    /// Called continuously while the slider value changes.
    func sliceChanged(to value: Float) {
        slicePosition = value
        updateSlice(highQuality: !isDragging)
    }

    /// Slider editing began / ended. Render a crisp frame once the drag settles.
    func sliceEditing(_ editing: Bool) {
        isDragging = editing
        if !editing { updateSlice(highQuality: true) }
    }

    func updateSlice(highQuality: Bool) {
        let (minVal, maxVal) = MRISlicing.extent(bounds, for: activeAxis)
        let clipCoord = minVal + (maxVal - minVal) * slicePosition
        let thickness: Float = 2.0
        let viewClipZ = MRISlicing.viewClip(forCoord: clipCoord)

        for node in allNodes {
            node.updateClipUniforms(viewClipZ: viewClipZ, thickness: thickness)
        }
        renderSnapshot(highQuality: highQuality)

        slicePlaneNode?.position = MRISlicing.planePosition(forCoord: clipCoord, axis: activeAxis)
    }

    /// Full-res multisampled snapshot when settled; smaller, cheaper frame while dragging.
    private func renderSnapshot(highQuality: Bool) {
        guard let renderer else { return }
        let dim: CGFloat = highQuality ? 512 : 256
        let aa: SCNAntialiasingMode = highQuality ? .multisampling4X : .none
        sliceImage = renderer.snapshot(atTime: 0, with: CGSize(width: dim, height: dim), antialiasingMode: aa)
    }

    func resetForReentry() {
        setupStarted = false
    }
}

// MARK: - Mini Brain SceneKit View

struct MiniBrainView: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitAngleMapping
        view.defaultCameraController.worldUp = SCNVector3(0, 0, 1)
        view.scene = scene
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
        }
    }
}

// MARK: - MRI View

struct MRIView: View {
    @State private var vm = MRIViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading MRI data…")
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(vm.activeAxis.title) MRI Slice")
                            .font(Theme.headingFont)
                            .foregroundColor(Theme.textPrimary)

                        Spacer()

                        Picker("Axis", selection: Binding(
                            get: { vm.activeAxis },
                            set: { vm.activeAxis = $0; vm.updateAxis() }
                        )) {
                            ForEach(MRIAxis.allCases) { axis in
                                Text(axis.title).tag(axis)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .accessibilityLabel("Slice plane")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer().frame(height: 12)

                    HStack(spacing: 8) {
                        ZStack {
                            Color(white: 0.05)

                            if let img = vm.sliceImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(8)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.bgCardStroke, lineWidth: 1)
                        )
                        .accessibilityLabel("\(vm.activeAxis.title) cross-section at \(Int(vm.slicePosition * 100)) percent")

                        MiniBrainView(scene: vm.miniBrainScene)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.bgCardStroke, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                            .accessibilityLabel("Mini brain showing slice plane location")
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 12)

                    VStack(spacing: 6) {
                        HStack {
                            Text(vm.activeAxis.labelStart)
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("Position: \(Int(vm.slicePosition * 100))%")
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text(vm.activeAxis.labelEnd)
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.horizontal, 4)

                        Slider(value: Binding(
                            get: { vm.slicePosition },
                            set: { vm.sliceChanged(to: $0) }
                        ), in: 0...1, onEditingChanged: { vm.sliceEditing($0) })
                        .tint(Theme.accent)
                        .accessibilityLabel("Slice position")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
        .onDisappear { vm.resetForReentry() }
    }
}
