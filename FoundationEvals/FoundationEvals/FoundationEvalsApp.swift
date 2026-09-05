//
//  FoundationEvalsApp.swift
//  FoundationEvals
//
//  Created by Cory Parry on 01/09/2026.
//

import AppKit
import SwiftUI

@main
@MainActor
struct FoundationEvalsApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(FoundationEvalsAppDelegate.self) private var appDelegate
    @State private var store: EvaluationStore
    @State private var mcpSettings: MCPSettingsController
    private let mcpRuntime: FoundationEvalsMCPRuntime

    init() {
        let store = EvaluationStore(supportDirectory: Self.acceptanceStorageDirectory)
        let runtime = FoundationEvalsMCPRuntime(store: store)
        let settings = MCPSettingsController(
            serverControl: MCPServerControl(
                start: { configuration in try await runtime.start(configuration) },
                stop: { await runtime.stop() }
            )
        )
        runtime.settingsController = settings
        _store = State(initialValue: store)
        _mcpSettings = State(initialValue: settings)
        mcpRuntime = runtime
    }

    private static var acceptanceStorageDirectory: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--evaluation-storage"),
           arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/") {
            return URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        }
        #endif
        return nil
    }

    var body: some Scene {
        WindowGroup(id: "evaluation-main", for: String.self) { _ in
            ContentView(store: store)
                .task(id: mcpSettings.installationState) {
                    appDelegate.runtime = mcpRuntime
                    guard !ProcessInfo.processInfo.arguments.contains("--disable-mcp-autostart") else { return }
                    guard mcpSettings.installationState == .installed else { return }
                    await mcpSettings.startServer()
                }
        } defaultValue: {
            "main"
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1_180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Evaluation") {
                Button("Show Suite Editor") {
                    store.selection = .suite
                    openWindow(id: "evaluation-main", value: "main")
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

        Settings {
            MCPSettingsView(controller: mcpSettings)
        }
    }
}

@MainActor
private final class FoundationEvalsAppDelegate: NSObject, NSApplicationDelegate {
    weak var runtime: FoundationEvalsMCPRuntime?
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task {
            await runtime.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
