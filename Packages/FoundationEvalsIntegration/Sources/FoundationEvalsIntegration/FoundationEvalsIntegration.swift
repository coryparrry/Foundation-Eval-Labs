/// Public integration package. Native `EvaluationResult` decoding stays in
/// FoundationEvalsAppleBridge so the workbench can ship without Xcode.
public enum FoundationEvalsIntegration: Sendable {
    public static let packageName = "FoundationEvalsIntegration"
}
