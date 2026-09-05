import SwiftUI

struct VisionToolControls: View {
    @Binding var configuration: EvaluationVisionToolConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image tools")
                .font(.headline)

            Toggle("OCR tool", isOn: $configuration.ocrEnabled)
                .accessibilityIdentifier("Enable OCR tool")
            Text("Allows the model to extract text from an image attached to the current prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Barcode reader tool", isOn: $configuration.barcodeEnabled)
                .accessibilityIdentifier("Enable barcode reader tool")
            Text("Allows the model to read machine-readable codes from an image attached to the current prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
