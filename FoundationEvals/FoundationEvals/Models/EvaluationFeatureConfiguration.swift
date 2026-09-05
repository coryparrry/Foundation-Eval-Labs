import Foundation

struct EvaluationFeatureConfiguration: Codable, Equatable, Sendable {
    static let maximumTools = 4
    static let maximumOutputFields = 8

    var tools: [EvaluationCustomToolDefinition]
    var profile: EvaluationProfileConfiguration
    var outputFields: [EvaluationSchemaField]
    var prewarm: Bool
    var streamResponse: Bool

    init(
        tools: [EvaluationCustomToolDefinition] = [],
        profile: EvaluationProfileConfiguration = .init(),
        outputFields: [EvaluationSchemaField] = [],
        prewarm: Bool = false,
        streamResponse: Bool = false
    ) {
        self.tools = tools
        self.profile = profile
        self.outputFields = outputFields
        self.prewarm = prewarm
        self.streamResponse = streamResponse
    }

    var validationIssue: String? {
        if tools.count > Self.maximumTools {
            return "A suite can define at most \(Self.maximumTools) custom tools."
        }
        if outputFields.count > Self.maximumOutputFields {
            return "An output schema can define at most \(Self.maximumOutputFields) fields."
        }
        if let issue = profile.validationIssue {
            return issue
        }
        if profile.enabled, profile.requireToolFirst, tools.isEmpty {
            return "A profile that requires a tool call must define at least one custom tool."
        }

        var toolIDs = Set<UUID>()
        var toolNames = Set<String>()
        for tool in tools {
            if let issue = tool.validationIssue {
                return issue
            }
            if !toolIDs.insert(tool.id).inserted {
                return "Custom tool IDs must be unique."
            }
            if !toolNames.insert(tool.name).inserted {
                return "Custom tool names must be unique."
            }
        }

        return Self.schemaValidationIssue(fields: outputFields, context: "Output schema")
    }

    static func schemaValidationIssue(
        fields: [EvaluationSchemaField],
        context: String
    ) -> String? {
        var fieldIDs = Set<UUID>()
        var fieldNames = Set<String>()
        for field in fields {
            if let issue = field.validationIssue {
                return "\(context): \(issue)"
            }
            if !fieldIDs.insert(field.id).inserted {
                return "\(context) field IDs must be unique."
            }
            if !fieldNames.insert(field.name).inserted {
                return "\(context) field names must be unique."
            }
        }
        return nil
    }
}

struct EvaluationProfileConfiguration: Codable, Equatable, Sendable {
    static let maximumNameCharacters = 80
    static let maximumInstructionsBytes = 4_096

    var enabled: Bool
    var name: String
    var afterToolInstructions: String
    var requireToolFirst: Bool

    init(
        enabled: Bool = false,
        name: String = "Tool workflow",
        afterToolInstructions: String = "",
        requireToolFirst: Bool = false
    ) {
        self.enabled = enabled
        self.name = name
        self.afterToolInstructions = afterToolInstructions
        self.requireToolFirst = requireToolFirst
    }

    var validationIssue: String? {
        if name.isEmpty {
            return "Profile name cannot be empty."
        }
        if name.count > Self.maximumNameCharacters {
            return "Profile name must be \(Self.maximumNameCharacters) characters or fewer."
        }
        if afterToolInstructions.utf8.count > Self.maximumInstructionsBytes {
            return "Profile instructions must be \(Self.maximumInstructionsBytes) UTF-8 bytes or fewer."
        }
        return nil
    }
}

enum EvaluationSchemaFieldType: String, Codable, CaseIterable, Identifiable, Sendable {
    case string
    case integer
    case number
    case boolean

    var id: Self { self }

    var title: String {
        switch self {
        case .string: "Text"
        case .integer: "Integer"
        case .number: "Number"
        case .boolean: "True or false"
        }
    }
}

struct EvaluationSchemaField: Identifiable, Codable, Equatable, Sendable {
    static let maximumNameCharacters = 64
    static let maximumDescriptionCharacters = 256

    var id: UUID
    var name: String
    var description: String
    var type: EvaluationSchemaFieldType
    var isOptional: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        description: String = "",
        type: EvaluationSchemaFieldType = .string,
        isOptional: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.isOptional = isOptional
    }

    var validationIssue: String? {
        if !EvaluationIdentifier.isValid(name, maximumCharacters: Self.maximumNameCharacters) {
            return "Field names must be identifiers of \(Self.maximumNameCharacters) characters or fewer."
        }
        if description.count > Self.maximumDescriptionCharacters {
            return "Field descriptions must be \(Self.maximumDescriptionCharacters) characters or fewer."
        }
        return nil
    }
}

enum EvaluationCustomToolMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixture
    case localHTTP

    var id: Self { self }

    var title: String {
        switch self {
        case .fixture: "Fixture response"
        case .localHTTP: "Local HTTP bridge"
        }
    }
}

struct EvaluationCustomToolDefinition: Identifiable, Codable, Equatable, Sendable {
    static let maximumNameCharacters = 64
    static let maximumDescriptionCharacters = 512
    static let maximumParameters = 8
    static let maximumEndpointCharacters = 512
    static let maximumArgumentBytes = 16_384
    static let maximumOutputBytes = 4_096
    static let requestTimeoutSeconds: TimeInterval = 10
    static let reservedMCPPort = 17_873

    var id: UUID
    var name: String
    var description: String
    var parameters: [EvaluationSchemaField]
    var mode: EvaluationCustomToolMode
    var fixtureResponse: String
    var endpoint: String

    init(
        id: UUID = UUID(),
        name: String = "",
        description: String = "",
        parameters: [EvaluationSchemaField] = [],
        mode: EvaluationCustomToolMode = .fixture,
        fixtureResponse: String = "",
        endpoint: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.parameters = parameters
        self.mode = mode
        self.fixtureResponse = fixtureResponse
        self.endpoint = endpoint
    }

    var validationIssue: String? {
        if !EvaluationIdentifier.isValid(name, maximumCharacters: Self.maximumNameCharacters) {
            return "Tool names must be identifiers of \(Self.maximumNameCharacters) characters or fewer."
        }
        if description.isEmpty {
            return "Tool \(name) needs a description."
        }
        if description.count > Self.maximumDescriptionCharacters {
            return "Tool descriptions must be \(Self.maximumDescriptionCharacters) characters or fewer."
        }
        if parameters.count > Self.maximumParameters {
            return "Tool \(name) can define at most \(Self.maximumParameters) parameters."
        }
        if let issue = EvaluationFeatureConfiguration.schemaValidationIssue(
            fields: parameters,
            context: "Tool \(name)"
        ) {
            return issue
        }
        if fixtureResponse.utf8.count > Self.maximumOutputBytes {
            return "Tool fixture output must be \(Self.maximumOutputBytes) UTF-8 bytes or fewer."
        }
        if endpoint.count > Self.maximumEndpointCharacters {
            return "Local tool endpoints must be \(Self.maximumEndpointCharacters) characters or fewer."
        }

        switch mode {
        case .fixture:
            break
        case .localHTTP:
            if let issue = Self.endpointValidationIssue(endpoint) {
                return issue
            }
        }
        return nil
    }

    func validatedEndpointURL() throws -> URL {
        if let issue = Self.endpointValidationIssue(endpoint) {
            throw EvaluationFeatureConfigurationError.invalid(issue)
        }
        guard let url = URL(string: endpoint) else {
            throw EvaluationFeatureConfigurationError.invalid("The local tool endpoint is not a valid URL.")
        }
        return url
    }

    private static func endpointValidationIssue(_ endpoint: String) -> String? {
        guard !endpoint.isEmpty, let components = URLComponents(string: endpoint) else {
            return "Local tools need an HTTP endpoint."
        }
        guard components.scheme == "http", components.host == "127.0.0.1" else {
            return "Local tool endpoints must use http://127.0.0.1 with an explicit port."
        }
        guard components.user == nil, components.password == nil else {
            return "Local tool endpoints cannot contain credentials."
        }
        guard components.query == nil, components.fragment == nil else {
            return "Local tool endpoints cannot contain a query or fragment."
        }
        guard let port = components.port, (1...65_535).contains(port) else {
            return "Local tool endpoints need an explicit port."
        }
        guard port != Self.reservedMCPPort else {
            return "Port \(Self.reservedMCPPort) is reserved for the FoundationEvals MCP server."
        }
        return nil
    }
}

enum EvaluationFeatureConfigurationError: LocalizedError, Sendable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let issue): issue
        }
    }
}

enum EvaluationIdentifier {
    static func isValid(_ value: String, maximumCharacters: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumCharacters else { return false }

        for (index, scalar) in value.unicodeScalars.enumerated() {
            let isUppercaseLetter = scalar.value >= 65 && scalar.value <= 90
            let isLowercaseLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            let isUnderscore = scalar.value == 95

            if index == 0 {
                guard isUppercaseLetter || isLowercaseLetter || isUnderscore else { return false }
            } else {
                guard isUppercaseLetter || isLowercaseLetter || isDigit || isUnderscore else { return false }
            }
        }
        return true
    }
}
