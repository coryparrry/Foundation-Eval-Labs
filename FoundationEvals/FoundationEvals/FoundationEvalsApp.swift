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
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Evaluation") {
                Button("Show Suite Editor") {
                    store.selection = .suite
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Add Test Case") {
                    store.selection = .suite
                    store.addCase()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store.isRunning || store.isProcessingFiles)

                Button("Add Reference Files…") {
                    store.selection = .suite
                    store.isImportingFiles = true
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(store.isRunning || store.isProcessingFiles)

                Divider()

                Button("Run Evaluation") {
                    store.startRun()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.isRunning || store.isProcessingFiles || store.runBlocker != nil)

                Button("Cancel Run") {
                    store.cancelRun()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isRunning)
            }
        }
    }
}
