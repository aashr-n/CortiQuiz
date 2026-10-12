import SwiftUI
import SceneKit

// MARK: - Learn Card

/// One study card. Hemisphere pairs are merged into a single card (both nodes
/// highlight together), mirroring how the quizzes treat left/right as one answer.
fileprivate struct LearnCard: Identifiable, Hashable {
    let id: String          // baseName, unique per card
    var baseName: String { id }
    let nodeIDs: [String]
    let hierarchyPath: [String]
    /// Highlights on both sides of the brain (left + right exist).
    var hasPair: Bool { nodeIDs.count > 1 }
    /// Broad region, shown as an optional hint (the immediate parent group).
    var region: String { hierarchyPath.last ?? "" }
}

// MARK: - Learn ViewModel

/// Flashcard study mode: one structure is highlighted in the ghost brain, you try
/// to recall it, then reveal the answer and self-rate. No score, no time pressure —
/// "Study again" simply re-queues the card until you mark it known.
@MainActor @Observable
final class LearnViewModel {
    var scene = SCNScene()
    var isLoading = true
    var loadFailed = false
    var recenterTrigger = false
    private(set) var explodeFactor: Float = 0

    fileprivate var currentCard: LearnCard?
    var revealed = false
    var hintShown = false
    var sessionComplete = false

    fileprivate private(set) var cards: [LearnCard] = []
    private var queue: [LearnCard] = []
    private(set) var learned: Set<String> = []
    /// Cards that needed more than one look this pass (study-again presses).
    private(set) var struggled: Set<String> = []

    var totalCount: Int { cards.count }
    var learnedCount: Int { learned.count }

    private var structureNodes: [String: SCNNode] = [:]
    private var explodeLayout = ExplodeLayout()
    private var hasLoaded = false

    /// Builds the scene off the main actor. Runs from SwiftUI's `.task`, so leaving the
    /// screen mid-load cancels it and a later visit starts over.
    func load() async {
        guard !hasLoaded else { return }
        let loaded = await Background.run {
            BrainSceneLoader.load { node, _ in
                node.applyColor(SceneColors.ghost)
            }
        }
        guard !Task.isCancelled else { return }
        hasLoaded = true
        guard !loaded.structures.isEmpty else {
            loadFailed = true
            isLoading = false
            return
        }

        scene = loaded.scene
        structureNodes = loaded.nodes
        explodeLayout = loaded.explodeLayout
        buildDeck(from: loaded.structures)
        startSession()
        isLoading = false
    }

    /// Merge hemisphere pairs into one card per base name, then order so structures
    /// flagged for review or missed in the quizzes surface first.
    private func buildDeck(from structures: [BrainStructure]) {
        var grouped: [String: [BrainStructure]] = [:]
        for s in structures { grouped[s.baseName, default: []].append(s) }

        let built: [LearnCard] = grouped.map { base, members in
            LearnCard(
                id: base,
                nodeIDs: members.map(\.id),
                hierarchyPath: members.first?.hierarchyPath ?? []
            )
        }

        let store = ProgressStore.shared
        let priority = Set(store.reviewQueue + store.weakestStructures(limit: 8))
        let priorityCards = built.filter { priority.contains($0.baseName) }.shuffled()
        let restCards = built.filter { !priority.contains($0.baseName) }.shuffled()
        cards = priorityCards + restCards
    }

    func startSession() {
        learned = []
        struggled = []
        sessionComplete = false
        setExplode(0)
        queue = cards
        advance()
    }

    func reveal() {
        guard !revealed else { return }
        Theme.tapHaptic()
        revealed = true
        applyHighlight()
    }

    func showHint() {
        guard !hintShown else { return }
        Theme.tapHaptic()
        hintShown = true
    }

    /// Mark the current card learned and move on.
    func markKnown() {
        guard let card = currentCard else { return }
        Theme.successHaptic()
        learned.insert(card.baseName)
        advance()
    }

    /// Re-queue the current card so it comes back around later this pass, and flag it so
    /// the next quiz asks it first.
    func markReview() {
        guard let card = currentCard else { return }
        Theme.tapHaptic()
        struggled.insert(card.baseName)
        ProgressStore.shared.flagForReview(card.baseName)
        queue.append(card)
        advance()
    }

    private func advance() {
        revealed = false
        hintShown = false
        guard !queue.isEmpty else {
            currentCard = nil
            sessionComplete = true
            return
        }
        currentCard = queue.removeFirst()
        applyHighlight()
    }

    private func applyHighlight() {
        guard let card = currentCard else { return }
        let targets = Set(card.nodeIDs)
        let highlight = revealed ? SceneColors.revealed : SceneColors.target

        restyleNodes(structureNodes) { id in
            targets.contains(id)
                ? (highlight, 1.0)
                : (SceneColors.ghost, SceneColors.ghostOpacity)
        }
    }

    func setExplode(_ factor: Float) {
        explodeFactor = factor
        explodeLayout.apply(factor, to: structureNodes)
    }
}

// MARK: - Learn View

struct LearnView: View {
    @State private var vm = LearnViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading study deck…", failed: vm.loadFailed)
            } else {
                VStack(spacing: 0) {
                    ProgressView(value: Double(vm.learnedCount), total: Double(max(vm.totalCount, 1)))
                        .tint(Theme.accent)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .accessibilityLabel("Learned \(vm.learnedCount) of \(vm.totalCount)")

                    ZStack(alignment: .bottom) {
                        SceneKitView(scene: vm.scene, recenterTrigger: vm.recenterTrigger)
                            .frame(maxHeight: .infinity)
                            .accessibilityLabel("3D brain with one structure highlighted. Rotate to inspect, then reveal the name.")

                        SceneControlsBar(
                            explodeFactor: Binding(get: { vm.explodeFactor }, set: { vm.setExplode($0) }),
                            onRecenter: { vm.recenterTrigger.toggle() }
                        )
                        .padding(12)
                    }

                    studyCard
                        .animation(.snappy, value: vm.revealed)
                        .bottomCard()
                }
            }
        }
        .navigationSubtitle(vm.isLoading ? "" : "\(vm.learnedCount) of \(vm.totalCount) learned · no score")
        .sessionSummary(isPresented: $vm.sessionComplete) { done in
            completionSummary(onDone: done)
        }
        .task { await vm.load() }
    }

    // MARK: Study card (front = recall prompt, back = answer + self-rating)

    @ViewBuilder
    private var studyCard: some View {
        if vm.revealed, let card = vm.currentCard {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(card.baseName)
                        .font(Theme.titleFont)
                        .multilineTextAlignment(.center)
                    if card.hasPair {
                        Text("Appears in both hemispheres")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if !card.hierarchyPath.isEmpty {
                        Text(card.hierarchyPath.joined(separator: " › "))
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button { vm.markReview() } label: {
                            Label("Study again", systemImage: "arrow.uturn.backward")
                                .font(Theme.headingFont)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        Button { vm.markKnown() } label: {
                            Label("Got it", systemImage: "checkmark")
                                .font(Theme.headingFont)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.correct.mix(with: .black, by: 0.25))
                    }
                    .controlSize(.large)
                }
            }
        } else {
            VStack(spacing: 14) {
                Text("What structure is highlighted?")
                    .font(Theme.headingFont)
                    .multilineTextAlignment(.center)

                if vm.hintShown, let region = vm.currentCard?.region, !region.isEmpty {
                    Label(region, systemImage: "lightbulb.fill")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }

                Button { vm.reveal() } label: {
                    Text("Reveal")
                        .font(Theme.headingFont)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                if let region = vm.currentCard?.region, !region.isEmpty, !vm.hintShown {
                    Button("Need a hint?") { vm.showHint() }
                        .font(Theme.bodyFont)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.hintShown)
        }
    }

    // MARK: Completion

    private func completionSummary(onDone: @escaping () -> Void) -> some View {
        SummarySheet(actionTitle: "Study Again", action: { vm.startSession() }, onDone: onDone) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)

            Text("Deck Complete")
                .font(Theme.titleFont)

            Text("You studied \(vm.totalCount) structure\(vm.totalCount == 1 ? "" : "s").")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if !vm.struggled.isEmpty {
                Label {
                    Text("\(vm.struggled.count) needed another look — they'll come up first next time you quiz.")
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.bgCard, in: .rect(cornerRadius: 20))
            }
        }
    }
}
