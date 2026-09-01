import Foundation
import FoundationModels

extension EvaluationModelConfiguration {
    static let judgeResponseTokenReserve = 1_024
    private static let judgeFixedTokenReserve = 1_024

    var generationOptions: GenerationOptions {
        GenerationOptions(
            samplingMode: resolvedSamplingMode,
            temperature: temperatureEnabled ? temperature : nil,
            maximumResponseTokens: maximumResponseTokens,
            toolCallingMode: referenceMode == .lookupTool ? .allowed : .disallowed
        )
    }

    var contextOptions: ContextOptions {
        ContextOptions(reasoningLevel: resolvedReasoningLevel)
    }

    var samplingSummary: String {
        switch samplingMode {
        case .automatic:
            return "Automatic"
        case .greedy:
            return "Greedy"
        case .topK:
            return "Random top \(topK)" + (seedEnabled ? " · seed \(seed)" : "")
        case .probability:
            return "Random p≤\(probabilityThreshold.formatted(.number.precision(.fractionLength(2))))"
                + (seedEnabled ? " · seed \(seed)" : "")
        }
    }

    func contextAllocation(
        contextSize: Int,
        includesModelJudge: Bool
    ) -> (effectiveInputLimit: Int, toolOutputReserve: Int, judgeOverheadReserve: Int) {
        let toolOutputReserve = referenceMode == .lookupTool
            ? maximumToolCalls * ReferenceLookupTool.contextTokenReservePerCall
            : 0
        let subjectAvailableInput = contextSize - maximumResponseTokens - toolOutputReserve
        let judgeOverheadReserve = includesModelJudge
            ? Self.judgeResponseTokenReserve + Self.judgeFixedTokenReserve + maximumResponseTokens + toolOutputReserve
            : 0
        let judgeAvailableInput = includesModelJudge ? contextSize - judgeOverheadReserve : contextSize
        let availableInput = max(1, min(subjectAvailableInput, judgeAvailableInput))
        let effectiveInputLimit = maximumInputTokens.map { min($0, availableInput) } ?? availableInput
        return (effectiveInputLimit, toolOutputReserve, judgeOverheadReserve)
    }

    private var resolvedSamplingMode: GenerationOptions.SamplingMode? {
        let resolvedSeed = seedEnabled ? seed : nil
        switch samplingMode {
        case .automatic:
            return nil
        case .greedy:
            return .greedy
        case .topK:
            return .random(top: topK, seed: resolvedSeed)
        case .probability:
            return .random(probabilityThreshold: probabilityThreshold, seed: resolvedSeed)
        }
    }

    private var resolvedReasoningLevel: ContextOptions.ReasoningLevel? {
        switch reasoningLevel {
        case .automatic:
            return nil
        case .light:
            return .light
        case .moderate:
            return .moderate
        case .deep:
            return .deep
        }
    }
}

extension LanguageModelCapabilities {
    var evaluationNames: [String] {
        [
            contains(.reasoning) ? "reasoning" : nil,
            contains(.toolCalling) ? "tool calling" : nil,
            contains(.guidedGeneration) ? "guided generation" : nil,
            contains(.vision) ? "vision" : nil
        ].compactMap { $0 }
    }
}
