import SwiftUI

struct ContentView: View {
    @State private var receiptText = ReceiptFixtures.discounted.text
    @State private var output: ReceiptOutput?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Receipt extractor")
                .font(.title2.weight(.semibold))
            Text("This screen calls the same production function as the capture tests.")
                .foregroundStyle(.secondary)
            TextEditor(text: $receiptText)
                .font(.body.monospaced())
                .frame(minHeight: 160)
                .border(.quaternary)
            Button("Extract") {
                Task { await extract() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            if let output {
                LabeledContent("Shop", value: output.shopName)
                LabeledContent("Date", value: output.date ?? "Missing")
                LabeledContent("Total pence", value: String(output.totalPence))
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
        .task { await extract() }
    }

    private func extract() async {
        errorMessage = nil
        do {
            output = try await ReceiptExtractor().evaluate(ReceiptInput(text: receiptText))
        } catch {
            output = nil
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
