//
//  FoundationEvalsApp.swift
//  FoundationEvals
//
//  Created by Cory Parry on 01/09/2026.
//

import SwiftUI

@main
struct FoundationEvalsApp: App {
    @State private var store = EvaluationStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .defaultSize(width: 1_180, height: 780)
        .commands {
            CommandMenu("Evaluation") {
                Button("Run Evaluation") {
                    store.startRun()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.isRunning)

                Button("Cancel Run") {
                    store.cancelRun()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isRunning)
            }
        }
    }
}
