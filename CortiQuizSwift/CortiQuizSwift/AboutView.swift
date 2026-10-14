import SwiftUI

/// Where the anatomy comes from, and a way to start over.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false
    private let store = ProgressStore.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        // The app icon (rendered from AppIcon.icon).
                        Image("AppIconArtwork")
                            .resizable()
                            .frame(width: 96, height: 96)
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                            .accessibilityHidden(true)
                        Text("CortiQuiz")
                            .font(Theme.displayFont)
                        Text(version)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Anatomy") {
                    Text("Every structure comes from the SPL-PNL Brain Atlas: 3D models segmented from the MRI of a healthy volunteer by the Surgical Planning Lab and the Psychiatry Neuroimaging Lab at Brigham and Women's Hospital.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Link(destination: URL(string: "http://www.spl.harvard.edu/publications/item/view/1265")!) {
                        Label("Cite the Atlas", systemImage: "quote.opening")
                    }
                    Link(destination: URL(string: "https://github.com/Slicer/Slicer/blob/master/License.txt")!) {
                        Label("3D Slicer License", systemImage: "doc.text")
                    }
                }

                Section {
                    LabeledContent("Questions Answered", value: "\(store.totalAnswered)")
                    LabeledContent("Structures Mastered", value: "\(store.masteredCount)")
                    Button("Reset Progress", role: .destructive) { confirmingReset = true }
                        .disabled(store.totalAnswered == 0 && store.reviewQueue.isEmpty)
                } header: {
                    Text("Progress")
                } footer: {
                    Text("Resetting clears your quiz history, best streak, and review list.")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset Progress", role: .destructive) { store.reset() }
            } message: {
                Text("This can't be undone.")
            }
        }
        .tint(Theme.accent)
    }
}
