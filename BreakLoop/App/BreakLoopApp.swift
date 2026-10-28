//
//  BreakLoopApp.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import SwiftUI

@main
struct BreakLoopApp: App {

    init() { AppLogger.shared.record("app_launched", category: .lifecycle) }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
