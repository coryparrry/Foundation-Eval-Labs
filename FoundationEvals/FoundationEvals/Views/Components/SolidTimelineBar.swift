import SwiftUI

/// Every measured span uses the same solid duration-bar appearance.
struct SolidTimelineBar: View {
    let width: CGFloat
    let offset: CGFloat
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: width, height: 10)
            .offset(x: offset)
    }
}
