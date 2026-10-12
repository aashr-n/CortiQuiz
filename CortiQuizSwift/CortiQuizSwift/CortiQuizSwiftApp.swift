//
//  CortiQuizSwiftApp.swift
//  CortiQuizSwift
//
//  Created by Aashray N on 3/2/26.
//

import SwiftUI

@main
struct CortiQuizSwiftApp: App {
    init() {
        Theme.applyNavigationBarFonts()
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
        }
    }
}
