import SwiftUI

/// Native sidebar sections must keep their own disclosure behavior. A custom
/// DisclosureGroupStyle otherwise replaces section rows with header content.
struct SidebarNavigationList<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    var body: some View {
        List(selection: $selection) {
            content()
        }
        .listStyle(.sidebar)
        .disclosureGroupStyle(.automatic)
    }
}
