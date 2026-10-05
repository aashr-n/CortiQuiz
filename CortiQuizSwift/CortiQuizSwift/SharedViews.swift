import SwiftUI

// MARK: - Loading

/// Spinner while a mode builds its scene, or an error if the atlas couldn't be loaded.
struct LoadingStateView: View {
    let message: String
    var failed = false

    var body: some View {
        VStack(spacing: 16) {
            if failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(Theme.textSecondary)
                Text("Couldn't load the brain atlas.")
                    .foregroundColor(Theme.textSecondary)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                Text(message)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Scene Controls

/// Slider that spreads structures out from the brain center.
struct ExplodeSlider: View {
    @Binding var value: Float

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .foregroundColor(Theme.textSecondary)
                .font(Theme.captionFont)
            Slider(value: $value, in: 0...3)
                .tint(Theme.accent)
                .accessibilityLabel("Explode view")
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundColor(Theme.textSecondary)
                .font(Theme.captionFont)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Theme.bgSecondary.opacity(0.8))
        .clipShape(Capsule())
    }
}

struct RecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "scope")
                .font(.title3)
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .accessibilityLabel("Recenter camera")
    }
}

/// Explode slider + recenter button, overlaid on the 3D view in Quiz and Learn modes.
struct SceneControlsBar: View {
    @Binding var explodeFactor: Float
    let onRecenter: () -> Void

    var body: some View {
        HStack {
            ExplodeSlider(value: $explodeFactor)
            Spacer()
            RecenterButton(action: onRecenter)
        }
    }
}

// MARK: - Bottom Card

extension View {
    /// Rounded card pinned under the 3D view (quiz answers, study card).
    func bottomCard() -> some View {
        self
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bgCard))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }
}
