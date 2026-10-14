import SwiftUI

// MARK: - Loading

/// Shown while a mode builds its scene, or an error if the atlas couldn't be loaded.
struct LoadingStateView: View {
    let message: String
    var failed = false

    var body: some View {
        if failed {
            ContentUnavailableView(
                "Couldn't Load the Atlas",
                systemImage: "exclamationmark.triangle",
                description: Text("The brain atlas files are missing or damaged.")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "brain")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.accent.gradient)
                    .symbolEffect(.breathe, options: .repeating)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
        }
    }
}

// MARK: - Stage Layout

/// A mode's two parts: the stage (the 3D brain or an MRI slice) and the panel that goes with
/// it (question and answers, the study card). Stacked on iPhone; side by side when the window
/// is wide (iPad landscape), with the panel as a column on the trailing side.
///
/// `AnyLayout` keeps the stage's identity when the arrangement flips, so rotating an iPad
/// doesn't rebuild the 3D view or lose the camera.
struct StageLayout<Stage: View, Panel: View>: View {
    @ViewBuilder var stage: Stage
    @ViewBuilder var panel: Panel

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width >= 700
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PanelContainer(wide: wide, maxHeight: geo.size.height * 0.62) { panel }
            }
        }
    }
}

/// The panel's card: under the stage with its bottom corners following the screen's, or
/// centered in a column beside it. Scrolls when its content doesn't fit (large text sizes).
private struct PanelContainer<Content: View>: View {
    let wide: Bool
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if wide {
            fitting
                .background(Theme.bgCard, in: .rect(cornerRadius: 32, style: .continuous))
                .frame(width: Theme.Metrics.sidePanelWidth)
                .frame(maxHeight: .infinity)
                .padding([.vertical, .trailing], 12)
        } else {
            CappedHeightLayout(maxHeight: maxHeight) { fitting }
                .background(Theme.bgCard, in: .rect(corners: .concentric(minimum: 28), isUniform: false))
                .padding([.horizontal, .bottom], 8)
        }
    }

    private var fitting: some View {
        let padded = content
            .padding(wide ? 24 : 20)
            .frame(maxWidth: wide ? .infinity : Theme.Metrics.panelMaxWidth)
            .frame(maxWidth: .infinity)
        return ViewThatFits(in: .vertical) {
            padded
            ScrollView { padded }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Sizes its one subview to its natural height, up to `maxHeight`, whatever height it's
/// offered, so a stack gives the rest to the stage. Placed at the capped height, a
/// `ViewThatFits` inside switches to its scrolling variant.
private struct CappedHeightLayout: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

// MARK: - Scene Controls

/// Slider that spreads structures out from the brain center, in a glass capsule.
struct ExplodeSlider: View {
    @Binding var value: Float

    var body: some View {
        Slider(value: $value, in: 0...3) {
            Text("Explode view")
        } minimumValueLabel: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
        } maximumValueLabel: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

struct RecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Recenter camera", systemImage: "scope")
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .help("Recenter camera")
    }
}

/// Explode slider + recenter button, floating over the 3D view.
struct SceneControlsBar: View {
    @Binding var explodeFactor: Float
    let onRecenter: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ExplodeSlider(value: $explodeFactor)
                RecenterButton(action: onRecenter)
            }
        }
        .frame(maxWidth: Theme.Metrics.panelMaxWidth)
    }
}

/// Small round glass button with an "xmark", for dismissing a selection.
struct ClearButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.bold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.secondary)
    }
}

// MARK: - Structure Info

/// A structure's name and where it sits in the atlas, for selection cards and the study card.
struct StructureTitle: View {
    let name: String
    let breadcrumb: String
    var serif = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(serif ? Theme.titleFont : Theme.headingFont)
                .fixedSize(horizontal: false, vertical: true)
            if !breadcrumb.isEmpty {
                Text(breadcrumb)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Session Progress

/// One segment per question in a session: green or red once answered, brighter for the
/// question on screen.
struct SessionProgressBar: View {
    let results: [Bool]
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(height: 4)
            }
        }
        .animation(.snappy, value: results.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session progress")
        .accessibilityValue("\(results.count(where: { $0 })) of \(results.count) correct so far, \(total) questions")
    }

    private func color(for index: Int) -> Color {
        if index < results.count { return results[index] ? Theme.correct : Theme.incorrect }
        if index == results.count { return Color.primary.opacity(0.6) }
        return Color.primary.opacity(0.14)
    }
}

// MARK: - Score Ring

/// Activity-style ring with a percentage in the middle. Fills in when it appears and
/// sweeps to new values.
struct ScoreRing: View {
    /// 0…1.
    let fraction: Double
    let caption: String
    var lineWidth: CGFloat = 10

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(colors: [Theme.accent.opacity(0.6), Theme.accent],
                                    center: .center,
                                    startAngle: .zero,
                                    endAngle: .degrees(360 * max(shown, 0.001))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(Theme.numberFont(.title3))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
        .onAppear { sweep() }
        .onChange(of: fraction) { sweep() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent \(caption)")
    }

    private func sweep() {
        guard !reduceMotion else {
            shown = fraction
            return
        }
        withAnimation(.smooth(duration: 0.9).delay(0.1)) { shown = fraction }
    }
}

// MARK: - Session Summary Sheet

/// End-of-session sheet layout: summary content, a primary action pinned to the bottom,
/// and Done (leave the mode) in the toolbar.
struct SummarySheet<Content: View>: View {
    let actionTitle: String
    let action: () -> Void
    let onDone: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) { content }
                    .frame(maxWidth: Theme.Metrics.panelMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            }
            .safeAreaBar(edge: .bottom) {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: Theme.Metrics.panelMaxWidth)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

/// Rounded tile with a colored label over a big number, for session summaries.
struct StatTile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(Theme.numberFont(.title2))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.bgCard, in: .rect(cornerRadius: Theme.Metrics.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `summary` as a sheet while `isPresented`. The closure's `done` action closes
    /// the sheet and then leaves the mode (back to the menu).
    func sessionSummary<Summary: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder summary: @escaping (_ done: @escaping () -> Void) -> Summary
    ) -> some View {
        modifier(SessionSummaryModifier(isPresented: isPresented, summary: summary))
    }
}

private struct SessionSummaryModifier<Summary: View>: ViewModifier {
    @Binding var isPresented: Bool
    let summary: (_ done: @escaping () -> Void) -> Summary

    @Environment(\.leaveMode) private var leaveMode
    /// Done was tapped: leave the mode once the sheet has finished closing.
    @State private var leaving = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            if leaving {
                leaving = false
                leaveMode()
            }
        }) {
            summary {
                leaving = true
                isPresented = false
            }
            .presentationDetents([.fraction(0.75), .large])
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Leaving a Mode

/// Closes the open mode and returns to the menu. Modes are shown in a split view's detail
/// column, where `dismiss` can't pop the root, so the menu provides this instead.
struct LeaveModeAction: Equatable {
    fileprivate let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func callAsFunction() { action() }

    /// There's only ever one: the menu's "close the open mode". Comparing equal keeps views
    /// that read it from updating whenever the menu does.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var leaveMode = LeaveModeAction {}
}
