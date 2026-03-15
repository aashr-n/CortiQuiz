import SwiftUI

struct MainMenuView: View {
    @State private var appear = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(hex: "0a0a1a"), Color(hex: "1a1a3e")],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    // Title
                    VStack(spacing: 8) {
                        Text("CortiQuiz")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, Color(hex: "8b5cf6")],
                                             startPoint: .leading, endPoint: .trailing)
                            )
                        Text("Brain Anatomy Trainer")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : -20)
                    
                    Spacer()
                    
                    // Mode Cards
                    VStack(spacing: 16) {
                        NavigationLink(destination: QuizView()) {
                            ModeCard(
                                icon: "brain.head.profile",
                                title: "Normal Mode",
                                subtitle: "Identify brain structures",
                                gradient: [Color(hex: "6366f1"), Color(hex: "8b5cf6")]
                            )
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 30)
                        
                        NavigationLink(destination: ExploreView()) {
                            ModeCard(
                                icon: "cube.transparent",
                                title: "Explore Mode",
                                subtitle: "Browse the full brain atlas",
                                gradient: [Color(hex: "06b6d4"), Color(hex: "3b82f6")]
                            )
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 30)
                        
                        NavigationLink(destination: MRIView()) {
                            ModeCard(
                                icon: "waveform.path.ecg",
                                title: "MRI Mode",
                                subtitle: "Dynamic brain cross-sections",
                                gradient: [Color(hex: "10b981"), Color(hex: "059669")]
                            )
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 30)
                        
                        NavigationLink(destination: MRIQuizView()) {
                            ModeCard(
                                icon: "brain.filled.head.profile",
                                title: "MRI Quiz",
                                subtitle: "Identify structures from slices",
                                gradient: [Color(hex: "14b8a6"), Color(hex: "0d9488")]
                            )
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 30)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    appear = true
                }
            }
        }
        .tint(.white)
    }
}

// MARK: - Mode Card

struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
