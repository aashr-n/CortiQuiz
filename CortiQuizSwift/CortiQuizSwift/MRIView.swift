import SwiftUI
import SceneKit

// MARK: - MRI ViewModel

@MainActor @Observable
final class MRIViewModel {
    var slicePosition: Float = 0.5
    var isLoading = true
    var loadFailed = false
    var sliceImage: UIImage?
    var miniBrainScene = SCNScene()
    var activeAxis: MRIAxis = .axial

    private var bounds = MiniBrainBounds()
    private var sliceRenderer: SliceRenderer?
    private var slicePlaneNode: SCNNode?
    private var isDragging = false
    /// Ticket of the frame on screen, so a late frame never replaces a newer one.
    private var shownTicket = 0
    private var hasLoaded = false

    /// Builds the slice and mini-brain scenes off the main actor. Runs from SwiftUI's
    /// `.task`, so leaving the screen mid-load cancels it and a later visit starts over.
    func load() async {
        guard !hasLoaded else { return }
        let assets = await Background.run {
            let loaded = BrainSceneLoader.load { node, s in
                node.installClipShader(color: UIColor(s.color))
            }
            let mini = MiniBrainBuilder.build(structures: loaded.structures, bounds: loaded.bounds)
            let renderer = SliceRenderer(scene: loaded.scene, nodes: loaded.ordered.map(\.node))
            return (loaded: loaded, mini: mini, renderer: renderer)
        }
        guard !Task.isCancelled else { return }
        hasLoaded = true
        guard !assets.loaded.structures.isEmpty else {
            loadFailed = true
            isLoading = false
            return
        }

        bounds = assets.loaded.bounds
        miniBrainScene = assets.mini.scene
        slicePlaneNode = assets.mini.planeNode
        sliceRenderer = assets.renderer
        isLoading = false
        updateAxis()
    }

    func updateAxis() {
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

    /// Moves the mini-brain plane right away and renders the slice on the render queue:
    /// a full-res multisampled frame when settled, a smaller cheaper one while dragging.
    func updateSlice(highQuality: Bool) {
        let (minVal, maxVal) = MRISlicing.extent(bounds, for: activeAxis)
        let coord = minVal + (maxVal - minVal) * slicePosition
        let axis = activeAxis
        slicePlaneNode?.position = MRISlicing.planePosition(forCoord: coord, axis: axis)

        guard let sliceRenderer else { return }
        Task {
            let frame = await sliceRenderer.run(dropIfSuperseded: true) { r in
                r.orient(axis)
                r.setSlice(coord: coord, thickness: 2)
                return highQuality
                    ? r.snapshot()
                    : r.snapshot(size: MRISlicing.snapshotSize / 2, antialiased: false)
            }
            guard let frame, frame.ticket > shownTicket else { return }
            shownTicket = frame.ticket
            sliceImage = frame.value
        }
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

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading MRI data…", failed: vm.loadFailed)
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
        .task { await vm.load() }
    }
}
