import SwiftUI

// MARK: - Loading

/// Spinner while a mode builds its scene, or an error if the atlas couldn't be loaded.
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
            ProgressView {
                Text(message)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.large)
        }
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
    }
}

// MARK: - Bottom Card

extension View {
    /// Card pinned under the 3D view or slice (quiz answers, study card). Its bottom
    /// corners follow the screen's.
    func bottomCard() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.bgCard, in: .rect(corners: .concentric(minimum: 28), isUniform: false))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }
}

// MARK: - Score Ring

/// Activity-style ring with a percentage in the middle.
struct ScoreRing: View {
    /// 0…1.
    let fraction: Double
    let caption: String
    var lineWidth: CGFloat = 10

    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [Theme.accent.opacity(0.6), Theme.accent],
                                    center: .center,
                                    startAngle: .zero,
                                    endAngle: .degrees(360 * fraction)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent \(caption)")
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
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
            }
            .safeAreaBar(edge: .bottom) {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
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

    @Environment(\.dismiss) private var dismiss
    /// Done was tapped: pop the mode once the sheet has finished closing.
    @State private var leaving = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            if leaving {
                leaving = false
                dismiss()
            }
        }) {
            summary {
                leaving = true
                isPresented = false
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
    }
}
