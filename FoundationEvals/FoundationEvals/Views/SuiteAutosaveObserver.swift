import SwiftUI

/// Keep whole-draft observation out of the navigation root, so a keystroke does
/// not also rebuild the history sidebar and navigation container.
struct SuiteAutosaveObserver: View {
    let store: EvaluationStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: store.draftSuite) { store.scheduleSuiteSave() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.refreshModelMetadata()
                } else {
                    store.saveSuite()
                }
            }
            .onDisappear { store.saveSuite() }
    }
}
