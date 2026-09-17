import SwiftUI
import UniformTypeIdentifiers

struct EvidenceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: EvaluationStore
    @State private var isChoosingFile = false
    @State private var preview: EvidenceImportPreview?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Evidence")
                .font(.title2.weight(.semibold))
            Text("Choose a .fevalrun folder, Apple evaluation-result JSON, or transcript JSON. Importing never runs code or grants approval.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Choose file or folder…") { isChoosingFile = true }
                .disabled(isLoading)

            if isLoading {
                ProgressView("Reading evidence…")
            }

            if let preview {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow { Text("Source"); Text(sourceTitle(preview.sourceKind)) }
                    GridRow { Text("File"); Text(preview.filename) }
                    GridRow { Text("Feature claim"); Text(preview.featureClaim.isEmpty ? "Unknown" : preview.featureClaim) }
                    GridRow { Text("Environment"); Text(preview.environmentSummary) }
                    GridRow { Text("Coverage"); Text(preview.coverageLabel) }
                    GridRow { Text("Destination"); Text("\(preview.destinationProjectName) · inspection-only") }
                    GridRow {
                        Text("Normalization")
                        Text(preview.canNormalize ? "Supported fields can be inspected" : EvaluationImportedLabels.originalFileOnly)
                    }
                }
                .font(.callout)

                ForEach(preview.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                switch preview.outcome {
                case .alreadyImported:
                    Text(EvaluationImportedLabels.alreadyImported)
                case .conflict:
                    Text(EvaluationImportedLabels.conflict)
                case .rejected:
                    Text("This file cannot be imported.")
                case .readyToImport:
                    EmptyView()
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    if let preview { store.discardImportedEvidencePreview(preview) }
                    dismiss()
                }
                Spacer()
                Button("Import") {
                    guard let preview else { return }
                    do {
                        _ = try store.confirmImportedEvidence(preview)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canImport)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.json, .folder],
            allowsMultipleSelection: false
        ) { result in
            Task { await load(result) }
        }
    }

    private var canImport: Bool {
        guard let preview, !isLoading else { return false }
        switch preview.outcome {
        case .readyToImport, .alreadyImported: return true
        case .conflict, .rejected: return false
        }
    }

    private func sourceTitle(_ kind: EvaluationImportedSourceKind) -> String {
        switch kind {
        case .captureBundle: "Foundation Evals capture folder"
        case .appleEvaluationResult: "Apple evaluation result"
        case .appleTranscript: "Apple transcript"
        case .unsupportedJSON: "Unsupported JSON"
        }
    }

    private func load(_ result: Result<[URL], Error>) async {
        errorMessage = nil
        if let preview { store.discardImportedEvidencePreview(preview) }
        preview = nil
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = try result.get().first else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            preview = try await store.previewImportedEvidence(at: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
