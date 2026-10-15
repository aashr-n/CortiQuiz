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
    var displayName: String { baseName.sentenceCased }
    /// Where it sits in the atlas; a pair's path drops "left"/"right".
    var breadcrumb: String { BrainStructure.breadcrumb(hierarchyPath, bothSides: hasPair) }
    /// Broad region, shown as an optional hint (the immediate parent group).
    var region: String {
        let parent = hierarchyPath.last ?? ""
        return (hasPair ? BrainStructure.computeBaseName(parent) : parent).sentenceCased
    }
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
                node.applyStyle(.ghost)
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

        // No fade for the first card: the scene isn't on screen yet.
        restyleNodes(structureNodes, duration: isLoading ? 0 : 0.25) { id in
            targets.contains(id) ? .solid(highlight) : .ghost
        }
        // Draw the eye to a new card's structure; small ones are easy to miss.
        for id in card.nodeIDs {
            if revealed { structureNodes[id]?.stopPulse() } else { structureNodes[id]?.pulseHighlight() }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// About the taller face (the answer), so revealing doesn't resize the stage.
    @ScaledMetric(relativeTo: .title2) private var cardHeight: CGFloat = 150

    var body: some View {
        ZStack {
            Theme.stage.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading study deck…", failed: vm.loadFailed)
            } else {
                StageLayout {
                    ZStack(alignment: .bottom) {
                        SceneKitView(scene: vm.scene, recenterTrigger: vm.recenterTrigger)
                            .accessibilityLabel("3D brain with one structure highlighted. Rotate to inspect, then reveal the name.")

                        SceneControlsBar(
                            explodeFactor: Binding(get: { vm.explodeFactor }, set: { vm.setExplode($0) }),
                            onRecenter: { vm.recenterTrigger.toggle() }
                        )
                        .padding(12)
                    }
                } panel: {
                    VStack(spacing: 16) {
                        ProgressView(value: Double(vm.learnedCount), total: Double(max(vm.totalCount, 1)))
                            .tint(Theme.accent)
                            .animation(.snappy, value: vm.learnedCount)
                            .accessibilityLabel("Learned \(vm.learnedCount) of \(vm.totalCount)")

                        studyCard
                    }
                }
            }
        }
        .navigationSubtitle(vm.isLoading ? "" : "\(vm.learnedCount) of \(vm.totalCount) learned")
        .sessionSummary(isPresented: $vm.sessionComplete) { done in
            completionSummary(onDone: done)
        }
        .task { await vm.load() }
    }

    // MARK: Study card (front = recall prompt, back = answer + self-rating)

    /// Flips over from the prompt to the answer. Only the face showing is built, so the
    /// answer isn't on screen (or read by VoiceOver) before Reveal.
    private var studyCard: some View {
        ZStack {
            if vm.revealed, let card = vm.currentCard {
                back(card)
                    .transition(reduceMotion ? .opacity : AnyTransition(CardFlip(isBack: true)))
            } else {
                front
                    .transition(reduceMotion ? .opacity : AnyTransition(CardFlip(isBack: false)))
            }
        }
        .frame(minHeight: cardHeight)
        // A new card starts face down without flipping back over. (Inner to the animation
        // below, so it wins when both change.)
        .transaction(value: vm.currentCard?.id) { $0.animation = nil }
        .animation(.spring(duration: 0.55, bounce: 0.2), value: vm.revealed)
    }

    private var front: some View {
        VStack(spacing: 14) {
            Text("What structure is highlighted?")
                .font(Theme.headingFont)
                .multilineTextAlignment(.center)

            Group {
                if let region = vm.currentCard?.region, !region.isEmpty {
                    if vm.hintShown {
                        Label(region, systemImage: "lightbulb.fill")
                            .foregroundStyle(Theme.textSecondary)
                            .transition(.blurReplace)
                    } else {
                        Button("Need a hint?") { vm.showHint() }
                            .transition(.blurReplace)
                    }
                }
            }
            .font(Theme.bodyFont)
            .animation(.easeInOut(duration: 0.2), value: vm.hintShown)

            Button { vm.reveal() } label: {
                Text("Reveal")
                    .font(Theme.headingFont)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    private func back(_ card: LearnCard) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(card.displayName)
                    .font(Theme.titleFont)
                    .multilineTextAlignment(.center)
                if card.hasPair {
                    Label("Both hemispheres", systemImage: "circle.lefthalf.filled")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                if !card.breadcrumb.isEmpty {
                    Text(card.breadcrumb)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .accessibilityElement(children: .combine)

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
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }
        }
    }

    // MARK: Completion

    private func completionSummary(onDone: @escaping () -> Void) -> some View {
        SummarySheet(actionTitle: "Study Again", action: { vm.startSession() }, onDone: onDone) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Deck Complete")
                    .font(Theme.displayFont)
                Text("You worked through all \(vm.totalCount) structures.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                StatTile(label: "First Try", value: "\(vm.totalCount - vm.struggled.count)",
                         icon: "checkmark.circle.fill", color: .secondary)
                StatTile(label: "Studied Again", value: "\(vm.struggled.count)",
                         icon: "arrow.uturn.backward.circle.fill", color: .secondary)
            }

            if !vm.struggled.isEmpty {
                Label {
                    Text("The ones you studied again come up first in your next quiz.")
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.bgCard, in: .rect(cornerRadius: Theme.Metrics.cardRadius))
            }
        }
    }
}

// MARK: - Card Flip

/// One face of a card flipping over its horizontal axis: the front turns away as the back
/// turns in from behind. Each face is only drawn while turned less than 90°, so the two
/// read as one solid card.
private struct CardFlip: Transition {
    let isBack: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(FlipRotation(angle: phase.isIdentity ? 0 : (isBack ? -180 : 180)))
    }
}

private struct FlipRotation: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .opacity(abs(angle) < 90 ? 1 : 0)
    }
}
