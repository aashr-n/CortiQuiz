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
    /// Structure tapped in the slice; highlighted in every slice and in the mini brain.
    private(set) var selected: BrainStructure?

    /// Index-aligned with `sliceRenderer.nodes`.
    private var structures: [BrainStructure] = []
    private var bounds = MiniBrainBounds()
    private var sliceRenderer: SliceRenderer?
    private var slicePlaneNode: SCNNode?
    private var miniNodes: [String: SCNNode] = [:]
    /// Colors the slice renders with: atlas colors, or the selection against `dimmedColors`.
    private var sliceColors: [UIColor] = []
    private var dimmedColors: [UIColor] = []
    private var isDragging = false
    /// Ticket of the frame on screen, so a late frame never replaces a newer one.
    private var shownTicket = 0
    private var hasLoaded = false

    /// World coordinate (mm) of the slice along the active axis.
    var sliceCoord: Float {
        let (lo, hi) = MRISlicing.extent(bounds, for: activeAxis)
        return lo + (hi - lo) * slicePosition
    }

    /// Builds the slice and mini-brain scenes off the main actor. Runs from SwiftUI's
    /// `.task`, so leaving the screen mid-load cancels it and a later visit starts over.
    func load() async {
        guard !hasLoaded else { return }
        let assets = await Background.run {
            let loaded = BrainSceneLoader.load { _, _ in }
            let mini = MiniBrainBuilder.build(structures: loaded.structures, bounds: loaded.bounds)
            let renderer = SliceRenderer(
                scene: loaded.scene,
                nodes: loaded.ordered.map(\.node),
                colors: loaded.structures.map { UIColor($0.color) },
                center: loaded.bounds.center
            )
            return (loaded: loaded, mini: mini, renderer: renderer)
        }
        guard !Task.isCancelled else { return }
        hasLoaded = true
        guard !assets.loaded.structures.isEmpty else {
            loadFailed = true
            isLoading = false
            return
        }

        structures = assets.loaded.structures
        bounds = assets.loaded.bounds
        miniBrainScene = assets.mini.scene
        miniNodes = assets.mini.nodeMap
        slicePlaneNode = assets.mini.planeNode
        sliceRenderer = assets.renderer
        sliceColors = assets.renderer.baseColors
        dimmedColors = assets.renderer.baseColors.map { SceneColors.mriDimmed($0, brightness: 0.35) }
        // Keep the spinner up until there's a slice to show.
        await updateSlice(highQuality: true).value
        isLoading = false
    }

    func setAxis(_ axis: MRIAxis) {
        activeAxis = axis
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

    /// Move the slice by whole millimetres (the step buttons).
    func step(_ millimetres: Float) {
        let (lo, hi) = MRISlicing.extent(bounds, for: activeAxis)
        slicePosition = min(max(slicePosition + millimetres / max(hi - lo, 1), 0), 1)
        updateSlice(highQuality: true)
    }

    /// Moves the mini-brain plane right away and renders the slice on the render queue:
    /// a sharp multisampled frame when settled, a smaller cheaper one while dragging.
    @discardableResult
    func updateSlice(highQuality: Bool) -> Task<Void, Never> {
        let axis = activeAxis
        let coord = sliceCoord
        if let slicePlaneNode {
            MRISlicing.placePlane(slicePlaneNode, axis: axis, coord: coord, bounds: bounds)
        }

        guard let sliceRenderer else { return Task {} }
        let colors = sliceColors
        return Task {
            let frame = await sliceRenderer.run(dropIfSuperseded: true) { r in
                r.orient(axis)
                r.setCut(coord: coord)
                r.setColors(colors)
                return highQuality
                    ? r.snapshot(size: MRISlicing.sharpSnapshotSize)
                    : r.snapshot(size: MRISlicing.snapshotSize / 2, antialiased: false)
            }
            guard let frame, frame.ticket > shownTicket else { return }
            shownTicket = frame.ticket
            sliceImage = frame.value
        }
    }

    /// Select the structure under a tap (`point` in unit image coordinates). Tapping
    /// outside every structure clears the selection.
    func identify(at point: CGPoint) {
        guard let sliceRenderer else { return }
        let axis = activeAxis
        let coord = sliceCoord
        Task {
            let hit = await sliceRenderer.run { r in
                r.orient(axis)
                r.setCut(coord: coord)
                return r.structureIndex(at: point)
            }
            let index = hit?.value ?? nil
            select(index.map { structures[$0] })
        }
    }

    /// Highlight `structure` (nil clears) in the slice and the mini brain, and re-render.
    func select(_ structure: BrainStructure?) {
        if structure != selected {
            if let old = selected, let node = miniNodes[old.id] {
                MiniBrainBuilder.highlight(node, color: nil)
            }
            selected = structure
            if let structure, let node = miniNodes[structure.id] {
                MiniBrainBuilder.highlight(node, color: SceneColors.selection)
            }
            if structure != nil { Theme.tapHaptic() }
        }
        if let structure {
            sliceColors = zip(structures, dimmedColors).map { s, dimmed in
                s.id == structure.id ? SceneColors.selection : dimmed
            }
        } else {
            sliceColors = sliceRenderer?.baseColors ?? []
        }
        // Always re-render: the pick request may have dropped a pending slider frame.
        updateSlice(highQuality: !isDragging)
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
        view.revealWhenPrepared(scene)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            view.revealWhenPrepared(scene)
        }
    }
}

// MARK: - Slice Frame

/// Square, rounded frame for a slice image, with the patient directions at its edges.
struct SliceFrame<Content: View>: View {
    let axis: MRIAxis
    @ViewBuilder let content: Content

    private let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)

    var body: some View {
        ZStack {
            Color(SceneColors.sliceBackground)
            ZStack { content }.padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(shape)
        .overlay { OrientationLabels(axis: axis) }
        .overlay(shape.stroke(Theme.bgCardStroke, lineWidth: 1))
    }
}

private struct OrientationLabels: View {
    let axis: MRIAxis

    var body: some View {
        let edges = axis.edgeLabels
        ZStack {
            letter(edges.top).frame(maxHeight: .infinity, alignment: .top)
            letter(edges.bottom).frame(maxHeight: .infinity, alignment: .bottom)
            letter(edges.left).frame(maxWidth: .infinity, alignment: .leading)
            letter(edges.right).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func letter(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(.caption2).weight(.bold))
            // On the slice, which stays dark in light mode too.
            .foregroundStyle(.white.opacity(0.6))
            .shadow(color: .black, radius: 2)
    }
}

// MARK: - Zoomable Slice

/// MRI Mode's slice image: pinch to zoom, drag to pan while zoomed, and tap to report the
/// tapped point in unit image coordinates. Zoom resets when `resetKey` changes.
private struct ZoomableSlice<Key: Equatable>: View {
    let image: UIImage?
    let resetKey: Key
    let label: String
    let onTap: (CGPoint) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let maxScale: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let liveScale = clampScale(scale * pinch)
            let liveOffset = clampOffset(
                CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                scale: liveScale, size: size
            )

            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(liveScale)
            .offset(liveOffset)
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = clampScale(scale * value.magnification)
                        offset = clampOffset(offset, scale: scale, size: size)
                    }
                    .simultaneously(with: DragGesture(minimumDistance: 10)
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            let moved = CGSize(width: offset.width + value.translation.width,
                                               height: offset.height + value.translation.height)
                            offset = clampOffset(moved, scale: scale, size: size)
                        }
                    )
            )
            .onTapGesture(coordinateSpace: .local) { location in
                onTap(unitPoint(location, size: size))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("mriSlice")
        }
        .overlay(alignment: .bottomTrailing) {
            if scale > 1 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { resetZoom() }
                } label: {
                    Label("Reset zoom", systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                        .font(Theme.font(.footnote).weight(.bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.primary)
                .padding(4)
            }
        }
        .onChange(of: resetKey) { resetZoom() }
    }

    private func resetZoom() {
        scale = 1
        offset = .zero
    }

    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, 1), maxScale)
    }

    /// Keep the zoomed image covering the frame.
    private func clampOffset(_ o: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2
        let maxY = (scale - 1) * size.height / 2
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    /// Frame point → unit point in the zoomed, panned image (which fills the frame at 1×).
    private func unitPoint(_ p: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: 0.5 + (p.x - size.width / 2 - offset.width) / (scale * size.width),
            y: 0.5 + (p.y - size.height / 2 - offset.height) / (scale * size.height)
        )
    }
}

// MARK: - MRI View

struct MRIView: View {
    @State private var vm = MRIViewModel()

    var body: some View {
        ZStack {
            Theme.stage.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading MRI data…", failed: vm.loadFailed)
            } else {
                StageLayout {
                    SliceFrame(axis: vm.activeAxis) {
                        ZoomableSlice(
                            image: vm.sliceImage,
                            resetKey: vm.activeAxis,
                            label: sliceDescription,
                            onTap: { vm.identify(at: $0) }
                        )
                    }
                    .padding(12)
                } panel: {
                    VStack(spacing: 18) {
                        axisPicker
                        selectionRow
                        sliceControls
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: vm.activeAxis)
        .task { await vm.load() }
    }

    private var sliceDescription: String {
        let base = "\(vm.activeAxis.title) cross-section at \(vm.activeAxis.locationLabel(vm.sliceCoord))"
        guard let s = vm.selected else { return base }
        return "\(base), \(s.displayName) highlighted"
    }

    private var axisPicker: some View {
        Picker("Slice plane", selection: Binding(
            get: { vm.activeAxis },
            set: { vm.setAxis($0) }
        )) {
            ForEach(MRIAxis.allCases) { axis in
                Text(axis.title).tag(axis)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }

    /// Mini brain (where the slice is) beside the tapped structure's name, or a hint.
    private var selectionRow: some View {
        HStack(spacing: 14) {
            MiniBrainView(scene: vm.miniBrainScene)
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Mini brain showing slice plane location")

            Group {
                if let s = vm.selected {
                    StructureTitle(name: s.displayName, breadcrumb: s.breadcrumb)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Tap a region to name it", systemImage: "hand.tap.fill")
                            .font(Theme.bodyFont)
                        Text("Pinch to zoom, drag to pan")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: vm.selected?.id)

            if vm.selected != nil {
                ClearButton(label: "Clear selection") { vm.select(nil) }
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var sliceControls: some View {
        let axis = vm.activeAxis
        return VStack(spacing: 8) {
            HStack {
                Text(axis.labelStart)
                Spacer()
                Text(axis.locationLabel(vm.sliceCoord))
                    .font(Theme.captionFont.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Spacer()
                Text(axis.labelEnd)
            }
            .font(Theme.captionFont)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    stepButton("chevron.left", by: -1, label: "Step 1 mm \(axis.labelStart.lowercased())")
                    Slider(value: Binding(
                        get: { vm.slicePosition },
                        set: { vm.sliceChanged(to: $0) }
                    ), in: 0...1, onEditingChanged: { vm.sliceEditing($0) })
                    .accessibilityLabel("Slice position")
                    .accessibilityValue(axis.locationLabel(vm.sliceCoord))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    stepButton("chevron.right", by: 1, label: "Step 1 mm \(axis.labelEnd.lowercased())")
                }
            }
        }
    }

    private func stepButton(_ icon: String, by millimetres: Float, label: String) -> some View {
        Button {
            vm.step(millimetres)
        } label: {
            Image(systemName: icon)
                .font(Theme.font(.body).weight(.bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}
