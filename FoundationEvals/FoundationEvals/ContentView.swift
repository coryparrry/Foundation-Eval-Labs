//
//  ContentView.swift
//  FoundationEvals
//
//  Created by Cory Parry on 01/09/2026.
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Label("Evaluation Suite", systemImage: "slider.horizontal.3")
                    .tag(SidebarSelection.suite)

                Section("Runs") {
                    ForEach(store.runs) { run in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.suiteName)
                                .lineLimit(1)
                            Text(run.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarSelection.run(run.id))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
        } detail: {
            switch store.selection {
            case .suite:
                SuiteEditorView(store: store)
            case .run(let id):
                if let run = store.run(with: id) {
                    RunDetailView(run: run)
                } else {
                    ContentUnavailableView("Run Not Found", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: store.suite) {
            store.saveSuite()
        }
        .alert(
            "Foundation Evals",
            isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )
        ) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }
}

#Preview {
    ContentView(store: EvaluationStore())
}
