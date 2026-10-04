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
    var recenterTrigger = false
    var explodeFactor: Float = 0

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
    private var originalPositions: [String: SCNVector3] = [:]
    private var brainCenter = SCNVector3Zero
    private var setupStarted = false

    private nonisolated static let backgroundColor = UIColor(white: 0.58, alpha: 1.0)
    private nonisolated static let backgroundOpacity: CGFloat = 0.16
    private nonisolated static let targetColor = UIColor(red: 0.96, green: 0.24, blue: 0.36, alpha: 1.0)

    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true

        Task.detached { [weak self] in
            let loaded = BrainSceneLoader.load { node, _ in
                node.applyColor(Self.backgroundColor)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scene = loaded.scene
                self.structureNodes = loaded.nodes
                self.originalPositions = loaded.nodeCenters
                self.brainCenter = loaded.center
                self.buildDeck(from: loaded.structures)
                self.startSession()
                self.isLoading = false
            }
        }
    }

    /// Merge hemisphere pairs into one card per base name, then order so structures
    /// the user has been missing in the quizzes surface first.
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

        let weakSpots = Set(ProgressStore.shared.weakestStructures(limit: 8))
        let weakCards = built.filter { weakSpots.contains($0.baseName) }.shuffled()
        let restCards = built.filter { !weakSpots.contains($0.baseName) }.shuffled()
        cards = weakCards + restCards
    }

    func startSession() {
        learned = []
        struggled = []
        sessionComplete = false
        explodeFactor = 0
        updateExplode()
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
        guard currentCard != nil else { return }
        Theme.successHaptic()
        learned.insert(currentCard!.baseName)
        advance()
    }

    /// Re-queue the current card so it comes back around later this pass.
    func markReview() {
        guard let card = currentCard else { return }
        Theme.tapHaptic()
        struggled.insert(card.baseName)
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
        let highlight = revealed ? UIColor(Theme.accent) : Self.targetColor

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        for (id, node) in structureNodes {
            if targets.contains(id) {
                node.applyColor(highlight)
                node.opacity = 1.0
            } else {
                node.applyColor(Self.backgroundColor)
                node.opacity = Self.backgroundOpacity
            }
        }
        SCNTransaction.commit()
    }

    func updateExplode() {
        let factor = explodeFactor
        for (id, node) in structureNodes {
            guard let orig = originalPositions[id] else { continue }
            node.position = SCNVector3(
                (orig.x - brainCenter.x) * factor,
                (orig.y - brainCenter.y) * factor,
                (orig.z - brainCenter.z) * factor
            )
        }
    }

    func resetForReentry() {
        setupStarted = false
    }
}

// MARK: - Learn View

struct LearnView: View {
    @State private var vm = LearnViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading study deck…")
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    progressHeader

                    ZStack(alignment: .bottom) {
                        SceneKitView(scene: vm.scene, recenterTrigger: vm.recenterTrigger)
                            .frame(maxHeight: .infinity)
                            .accessibilityLabel("3D brain with one structure highlighted. Rotate to inspect, then reveal the name.")

                        sceneControls
                            .padding(12)
                    }

                    studyCard
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bgCard))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }

            if vm.sessionComplete {
                Color.black.opacity(0.7).ignoresSafeArea()
                completionCard
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.sessionComplete)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
        .onDisappear { vm.resetForReentry() }
    }

    // MARK: Header

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Label("\(vm.learnedCount)/\(vm.totalCount)", systemImage: "checkmark.seal.fill")
                    .foregroundColor(Theme.accent)
                    .font(Theme.headingFont)
                    .accessibilityLabel("Learned \(vm.learnedCount) of \(vm.totalCount)")
                Spacer()
                Text("No score · learn at your pace")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
            }
            ProgressView(value: Double(vm.learnedCount), total: Double(max(vm.totalCount, 1)))
                .tint(Theme.accent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: Scene controls (explode + recenter) — shared idiom with the quiz modes.

    private var sceneControls: some View {
        HStack {
            HStack {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .foregroundColor(Theme.textSecondary)
                    .font(Theme.captionFont)
                Slider(value: Binding(
                    get: { vm.explodeFactor },
                    set: { vm.explodeFactor = $0; vm.updateExplode() }
                ), in: 0...3)
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

            Spacer()

            Button {
                vm.recenterTrigger.toggle()
            } label: {
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

    // MARK: Study card (front = recall prompt, back = answer + self-rating)

    @ViewBuilder
    private var studyCard: some View {
        if vm.revealed, let card = vm.currentCard {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(card.baseName)
                        .font(Theme.titleFont)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    if card.hasPair {
                        Text("appears on both hemispheres")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textTertiary)
                    }
                    if !card.hierarchyPath.isEmpty {
                        Text(card.hierarchyPath.joined(separator: " → "))
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 12) {
                    Button { vm.markReview() } label: {
                        Label("Study again", systemImage: "arrow.uturn.left")
                            .font(Theme.headingFont)
                            .foregroundColor(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    Button { vm.markKnown() } label: {
                        Label("Got it", systemImage: "checkmark")
                            .font(Theme.headingFont)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.correct)
                            .clipShape(Capsule())
                    }
                }
            }
        } else {
            VStack(spacing: 14) {
                Text("What structure is highlighted?")
                    .font(Theme.headingFont)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                if vm.hintShown, let region = vm.currentCard?.region, !region.isEmpty {
                    Text("Region · \(region)")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                        .transition(.opacity)
                }

                Button { vm.reveal() } label: {
                    Text("Reveal")
                        .font(Theme.headingFont)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }

                if let region = vm.currentCard?.region, !region.isEmpty, !vm.hintShown {
                    Button { vm.showHint() } label: {
                        Text("Need a hint?")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.hintShown)
        }
    }

    // MARK: Completion

    private var completionCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.accent)

            Text("Deck complete")
                .font(Theme.titleFont)
                .foregroundColor(Theme.textPrimary)

            Text("You studied \(vm.totalCount) structure\(vm.totalCount == 1 ? "" : "s").")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if !vm.struggled.isEmpty {
                Text("\(vm.struggled.count) needed another look — they'll come up first next time you quiz.")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Button { vm.startSession() } label: {
                Text("Study Again")
                    .font(Theme.headingFont)
                    .foregroundColor(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Study again")
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.bgSecondary)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.bgCardStroke, lineWidth: 1))
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}
