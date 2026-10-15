//
//  CortiQuizSwiftApp.swift
//  CortiQuizSwift
//
//  Created by Aashray N on 3/2/26.
//

import SwiftUI

@main
struct CortiQuizSwiftApp: App {
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    init() {
        Theme.applyUIKitFonts()
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .font(Theme.font(.body))
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

/// Light or dark, chosen in About; follows the system unless set.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
