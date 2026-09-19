import SwiftUI

#Preview("Dashboard · Light") {
    WorkspaceOverviewView(store: dashboardPreviewStore())
        .frame(width: 1_000, height: 800)
        .preferredColorScheme(.light)
}

#Preview("Dashboard · Dark, compact") {
    WorkspaceOverviewView(store: dashboardPreviewStore())
        .frame(width: 730, height: 1_100)
        .preferredColorScheme(.dark)
}

@MainActor
private func dashboardPreviewStore() -> EvaluationStore {
    // Previews never read or change the developer's saved workspace.
    EvaluationStore(supportDirectory: FileManager.default.temporaryDirectory
        .appending(path: "FoundationEvals-Dashboard-Preview-\(UUID().uuidString)"))
}
