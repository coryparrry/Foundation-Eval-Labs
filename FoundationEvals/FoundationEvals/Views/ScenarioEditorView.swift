import SwiftUI

struct ScenarioEditorView: View {
    @Bindable var coordinator: ScenarioCoordinator

    @State private var page: ScenarioEditorPage = .outcome

    var body: some View {
        IntentLabEditorLayout(heading: "SCENARIO", selection: $page) {
            switch page {
            case .outcome: outcomeSection
            case .fixture: fixtureSection
            case .evidence: evidenceSection
            case .parameters: parametersSection
            case .assertions: assertionsSection
            case .settings: settingsSection
            }
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: coordinator.draft.safety.mutationPolicy) { _, policy in
            if policy == .syntheticMutation { coordinator.draft.coverage.siriAttemptCount = 1 }
        }
    }

    private var outcomeSection: some View {
        IntentLabCard(
            "Define the expected outcome",
            subtitle: "Set the request and observable result. Saved wording stays the same on every run."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                labeledRow("Scenario name") {
                    TextField("Scenario name", text: $coordinator.draft.name)
                }
                labeledRow("App bundle ID") {
                    TextField("com.example.App", text: $coordinator.draft.target.bundleIdentifier)
                }
                labeledRow("Approved request") {
                    TextField("What should Siri process?", text: $coordinator.draft.goal.requestText, axis: .vertical)
                        .lineLimit(2...4)
                }
                labeledRow("Expected behavior") {
                    TextField("Describe only observable behavior", text: $coordinator.draft.goal.expectedBehavior, axis: .vertical)
                        .lineLimit(2...5)
                }
                labeledRow("Language") {
                    TextField("en-GB", text: $coordinator.draft.goal.languageCode)
                }
            }
        }
    }

    private var fixtureSection: some View {
        IntentLabCard("Intent and fixture", subtitle: "Choose the intent to invoke and the test data it uses.") {
            VStack(alignment: .leading, spacing: 10) {
                labeledRow("Fixture ID") {
                    TextField("packing-notes", text: $coordinator.draft.fixture.id)
                }
                labeledRow("Fixture version") {
                    TextField("1", text: $coordinator.draft.fixture.version)
                }
                labeledRow("Fixture digest") {
                    TextField("Stable fixture digest", text: $coordinator.draft.fixture.digest)
                }
                labeledRow("Intent definition") {
                    TextField("OpenNoteIntent", text: $coordinator.draft.directControl.intentIdentifier)
                }
                labeledRow("Invocation route") {
                    Picker("Invocation route", selection: $coordinator.draft.target.route) {
                        Text("App Shortcut").tag(ScenarioInvocationRoute.appShortcut)
                        Text("App Intent definition").tag(ScenarioInvocationRoute.appIntentDefinition)
                    }
                    .labelsHidden()
                }
                labeledRow("Synthetic fixture") {
                    Toggle("Synthetic fixture", isOn: $coordinator.draft.fixture.isSynthetic)
                        .labelsHidden()
                }
                labeledRow("Fixture preparation") {
                    TextField("resetFixture", text: $coordinator.draft.fixture.preparationOperation)
                }
                labeledRow("Fixture cleanup") {
                    TextField("resetFixture", text: $coordinator.draft.fixture.cleanupOperation)
                }
                labeledRow("Linked feature run") {
                    TextField("Optional feature run UUID", text: linkedFeatureRunID)
                }
            }
            .textFieldStyle(.roundedBorder)

        }
    }

    private var evidenceSection: some View {
        IntentLabCard("Required evidence lanes", subtitle: "Choose which results must pass for this scenario.") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    requirementPickers
                }
                VStack(alignment: .leading, spacing: 10) {
                    requirementPickers
                }
            }

        }
    }

    private var parametersSection: some View {
        IntentLabCard("Declared parameters", subtitle: "Inputs passed to the intent.") {
            HStack {
                Spacer()
                Button("Add parameter", systemImage: "plus") {
                    coordinator.draft.directControl.parameters.append(
                        .init(name: "parameter", type: .primitive(.string), isOptional: false, presence: .missing)
                    )
                    coordinator.draft.definitionDigest = ""
                }
                .buttonStyle(.borderless)
            }
            ForEach(Array(coordinator.draft.directControl.parameters.indices), id: \.self) { index in
                ScenarioParameterEditor(parameter: $coordinator.draft.directControl.parameters[index]) {
                    coordinator.draft.directControl.parameters.remove(at: index)
                    coordinator.draft.definitionDigest = ""
                }
            }

        }
    }

    private var assertionsSection: some View {
        IntentLabCard("Outcome assertions", subtitle: "Observations required to pass.") {
            HStack {
                Spacer()
                Button("Add assertion", systemImage: "plus") {
                    coordinator.draft.assertions.append(
                        .init(
                            kind: .returnedField,
                            observationKey: "observation",
                            expectedValue: .string(""),
                            explanation: "Describe what this observation proves."
                        ))
                    coordinator.draft.definitionDigest = ""
                }
                .buttonStyle(.borderless)
            }
            ForEach($coordinator.draft.assertions) { $assertion in
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            assertionControls(assertion: $assertion)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            assertionControls(assertion: $assertion)
                        }
                    }
                    ScenarioExpectedValueEditor(value: $assertion.expectedValue)
                    TextField("What this proves", text: $assertion.explanation)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

        }
    }

    private var settingsSection: some View {
        IntentLabCard("Run settings", subtitle: "Configure safety, attempts and saved versions.") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Safety", selection: $coordinator.draft.safety.mutationPolicy) {
                        Text("Read-only").tag(ScenarioMutationPolicy.readOnly)
                        Text("Synthetic mutation").tag(ScenarioMutationPolicy.syntheticMutation)
                    }
                    Picker("Case set", selection: $coordinator.draft.caseSet) {
                        Text("Regression").tag(ScenarioCaseSet?.some(.regression))
                        Text("Holdout").tag(ScenarioCaseSet?.some(.holdout))
                    }
                    Stepper("Siri attempts: \(siriAttemptCount.wrappedValue)", value: siriAttemptCount, in: 1...3)
                        .disabled(coordinator.draft.safety.mutationPolicy == .syntheticMutation)
                }
                HStack(spacing: 12) {
                    TextField(
                        "Deadline (seconds)",
                        value: $coordinator.draft.safety.deadlineSeconds,
                        format: .number.precision(.fractionLength(0))
                    )
                    .frame(maxWidth: 190)
                    TextField("Allowed actions, comma separated", text: allowedActions)
                }
                TextField(
                    "Intentional comparison changes for next run, comma separated",
                    text: statedChangedDimensions
                )
                HStack {
                    Spacer()
                    Button("New frozen version") { coordinator.duplicateAsNewVersion() }
                    Button("Freeze and save") {
                        Task {
                            do { try await coordinator.freezeAndSave() } catch { coordinator.notice = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            validationSummary
            requestSuggestions
        }
    }

    @ViewBuilder private var requirementPickers: some View {
        requirementPicker("App feature", selection: $coordinator.draft.coverage.appFeature)
        requirementPicker("Intent integration", selection: $coordinator.draft.coverage.intentIntegration)
        requirementPicker("Siri", selection: $coordinator.draft.coverage.siri)
    }

    @ViewBuilder private func assertionControls(assertion: Binding<ScenarioAssertion>) -> some View {
        Picker("Kind", selection: assertion.kind) {
            ForEach(ScenarioAssertionKind.allCases, id: \.self) {
                Text(assertionTitle($0)).tag($0)
            }
        }
        TextField("Observation key", text: assertion.observationKey)
        Toggle("Required", isOn: assertion.required)
        Button("Remove", systemImage: "trash", role: .destructive) {
            coordinator.draft.assertions.removeAll { $0.id == assertion.wrappedValue.id }
            coordinator.draft.definitionDigest = ""
        }
        .labelStyle(.iconOnly)
    }

    private var validationSummary: some View {
        let issues = coordinator.currentValidationIssues
        return Group {
            if !issues.isEmpty {
                DisclosureGroup("Definition checks · \(issues.count)") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(issues) { issue in
                            Label(issue.message, systemImage: issue.severity == .error ? "xmark.circle" : "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var requestSuggestions: some View {
        DisclosureGroup("Explore request wording") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Foundation Models generates review candidates only. Nothing is added to the regression scenario until you approve it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(
                    coordinator.isGeneratingSuggestions ? "Generating…" : "Generate candidates",
                    systemImage: "sparkles"
                ) {
                    Task { await coordinator.generateSuggestions() }
                }
                .disabled(coordinator.isGeneratingSuggestions)
                ForEach(coordinator.suggestions) { suggestion in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.requestText).font(.callout.weight(.medium))
                            Text("\(suggestion.category) · \(suggestion.note)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(suggestion.approved ? "Approved" : "Use") {
                            coordinator.approveSuggestion(id: suggestion.id)
                        }
                        .disabled(suggestion.approved)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 6)
        }
    }

    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            content().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func requirementPicker(_ title: String, selection: Binding<ScenarioLaneRequirement>) -> some View {
        Picker(title, selection: selection) {
            Text("Required").tag(ScenarioLaneRequirement.required)
            Text("Optional").tag(ScenarioLaneRequirement.optional)
            Text("Not applicable").tag(ScenarioLaneRequirement.notApplicable)
        }
    }

    private func assertionTitle(_ kind: ScenarioAssertionKind) -> String {
        switch kind {
        case .entityIdentifier: "Entity ID"
        case .returnedField: "Returned field"
        case .visibleText: "Visible text"
        case .stateTransition: "State change"
        case .noMutation: "No mutation"
        case .semanticRubric: "Semantic review"
        }
    }

    private var linkedFeatureRunID: Binding<String> {
        Binding(
            get: { coordinator.draft.directControl.linkedFeatureRunID?.uuidString ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                coordinator.draft.directControl.linkedFeatureRunID = trimmed.isEmpty ? nil : UUID(uuidString: trimmed)
            }
        )
    }

    private var allowedActions: Binding<String> {
        Binding(
            get: { coordinator.draft.safety.allowedActions.joined(separator: ", ") },
            set: { text in
                coordinator.draft.safety.allowedActions = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var statedChangedDimensions: Binding<String> {
        Binding(
            get: { coordinator.statedChangedDimensions.sorted().joined(separator: ", ") },
            set: { text in
                coordinator.statedChangedDimensions = Set(
                    text.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
        )
    }

    private var siriAttemptCount: Binding<Int> {
        Binding(
            get: { coordinator.draft.coverage.siriAttemptCount ?? 3 },
            set: { coordinator.draft.coverage.siriAttemptCount = $0 }
        )
    }
}

private struct ScenarioParameterEditor: View {
    @Binding var parameter: ScenarioParameter
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack { parameterControls }
                VStack(alignment: .leading, spacing: 8) { parameterControls }
            }
            valueEditor
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var parameterControls: some View {
        TextField("Parameter name", text: $parameter.name)
        Picker("Type", selection: typeSelection) {
            ForEach(ParameterEditorType.allCases) { type in Text(type.title).tag(type) }
        }
        Toggle("Optional", isOn: $parameter.isOptional)
        Picker("Presence", selection: presenceSelection) {
            Text("Missing").tag(ParameterPresenceChoice.missing)
            Text("Set value").tag(ParameterPresenceChoice.value)
            Text("Explicit null").tag(ParameterPresenceChoice.null)
        }
        Button("Remove", systemImage: "trash", role: .destructive, action: remove)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("Remove parameter")
    }

    @ViewBuilder private var valueEditor: some View {
        if case .missing = parameter.presence {
            Text("The dynamic setter is not called; the intent's default or required-parameter behavior remains observable.")
                .font(.caption).foregroundStyle(.secondary)
        } else if case .value(.null) = parameter.presence {
            Text(parameter.isOptional
                 ? "The dynamic setter receives nil explicitly."
                 : "Explicit null requires an optional parameter.")
                .font(.caption)
                .foregroundStyle(parameter.isOptional ? Color.secondary : Color.red)
        } else {
            switch parameter.type {
            case .primitive(.string):
                TextField("String value", text: stringValue)
            case .primitive(.boolean):
                Toggle("Boolean value", isOn: boolValue)
            case .primitive(.integer):
                TextField("Integer value", value: integerValue, format: .number)
            case .primitive(.number):
                TextField("Finite number", value: numberValue, format: .number)
            case .primitive(.date):
                DatePicker("Resolved instant", selection: dateValue)
            case .enumeration:
                HStack {
                    TextField("Enum type identifier", text: enumTypeIdentifier)
                    TextField("Allowed cases, comma separated", text: enumAllowedCases)
                    Picker("Enum case", selection: enumValue) {
                        ForEach(enumCases, id: \.self) { Text($0).tag($0) }
                    }
                }
            case .entity:
                HStack {
                    TextField("Entity type identifier", text: entityTypeIdentifier)
                    TextField("Stable entity identifier", text: entityValue)
                }
            case .array:
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Array item type", selection: arrayElementSelection) {
                        Text("String").tag(ParameterEditorType.string)
                        Text("Boolean").tag(ParameterEditorType.boolean)
                        Text("Integer").tag(ParameterEditorType.integer)
                        Text("Number").tag(ParameterEditorType.number)
                    }
                    TextField("Comma-separated values", text: arrayValues)
                    Text("Arrays are homogeneous. Invalid booleans and numbers are rejected before Xcode runs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var presenceSelection: Binding<ParameterPresenceChoice> {
        Binding(
            get: {
                switch parameter.presence {
                case .missing: .missing
                case .value(.null): .null
                case .value: .value
                }
            },
            set: { choice in
                switch choice {
                case .missing: parameter.presence = .missing
                case .value: parameter.presence = defaultPresence(for: parameter.type)
                case .null: parameter.presence = .value(.null)
                }
            }
        )
    }

    private var typeSelection: Binding<ParameterEditorType> {
        Binding(
            get: { ParameterEditorType(parameter.type) },
            set: { newValue in
                parameter.type = newValue.valueType
                parameter.presence = .missing
            }
        )
    }

    private var stringValue: Binding<String> { valueBinding(default: "", get: { if case .string(let value) = $0 { value } else { nil } }, wrap: ScenarioValue.string) }
    private var boolValue: Binding<Bool> { valueBinding(default: false, get: { if case .boolean(let value) = $0 { value } else { nil } }, wrap: ScenarioValue.boolean) }
    private var integerValue: Binding<Int64> { valueBinding(default: 0, get: { if case .integer(let value) = $0 { value } else { nil } }, wrap: ScenarioValue.integer) }
    private var numberValue: Binding<Double> { valueBinding(default: 0, get: { if case .number(let value) = $0 { value } else { nil } }, wrap: ScenarioValue.number) }
    private var dateValue: Binding<Date> {
        valueBinding(default: Date(), get: { if case .date(let value) = $0 { value.resolvedInstant } else { nil } }) {
            .date(.init(source: ISO8601DateFormatter().string(from: $0), timeZoneIdentifier: TimeZone.current.identifier, resolvedInstant: $0))
        }
    }
    private var enumValue: Binding<String> {
        let typeIdentifier: String
        let first: String
        if case .enumeration(let type, let cases) = parameter.type {
            typeIdentifier = type
            first = cases.first ?? "case"
        } else { typeIdentifier = "Enum"; first = "case" }
        return valueBinding(default: first, get: { if case .enumeration(let value) = $0 { value.caseIdentifier } else { nil } }) {
            .enumeration(.init(typeIdentifier: typeIdentifier, caseIdentifier: $0))
        }
    }
    private var enumCases: [String] {
        guard case .enumeration(_, let cases) = parameter.type else { return [] }
        return cases
    }
    private var enumTypeIdentifier: Binding<String> {
        Binding(
            get: { if case .enumeration(let type, _) = parameter.type { type } else { "" } },
            set: { newValue in
                guard case .enumeration(_, let cases) = parameter.type else { return }
                parameter.type = .enumeration(typeIdentifier: newValue, allowedCases: cases)
                if case .value(.enumeration(var value)) = parameter.presence {
                    value.typeIdentifier = newValue
                    parameter.presence = .value(.enumeration(value))
                }
            }
        )
    }
    private var enumAllowedCases: Binding<String> {
        Binding(
            get: { enumCases.joined(separator: ", ") },
            set: { text in
                guard case .enumeration(let type, _) = parameter.type else { return }
                let cases = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                parameter.type = .enumeration(typeIdentifier: type, allowedCases: cases)
                if case .value(.enumeration(let value)) = parameter.presence, !cases.contains(value.caseIdentifier) {
                    parameter.presence = .value(.enumeration(.init(typeIdentifier: type, caseIdentifier: cases.first ?? "")))
                }
            }
        )
    }
    private var entityTypeIdentifier: Binding<String> {
        Binding(
            get: { if case .entity(let type) = parameter.type { type } else { "" } },
            set: { newValue in
                parameter.type = .entity(typeIdentifier: newValue)
                if case .value(.entity(var value)) = parameter.presence {
                    value.typeIdentifier = newValue
                    parameter.presence = .value(.entity(value))
                }
            }
        )
    }
    private var entityValue: Binding<String> {
        let typeIdentifier = if case .entity(let type) = parameter.type { type } else { "Entity" }
        return valueBinding(default: "", get: { if case .entity(let value) = $0 { value.identifier } else { nil } }) {
            .entity(.init(typeIdentifier: typeIdentifier, identifier: $0))
        }
    }

    private var arrayElementSelection: Binding<ParameterEditorType> {
        Binding(
            get: {
                guard case .array(let element) = parameter.type else { return .string }
                return ParameterEditorType(element)
            },
            set: { selection in
                let element = selection.valueType
                parameter.type = .array(element: element)
                parameter.presence = .value(.array([]))
            }
        )
    }

    private var arrayValues: Binding<String> {
        Binding(
            get: {
                guard case .value(.array(let values)) = parameter.presence else { return "" }
                return values.map { value in
                    switch value {
                    case .string(let item): item
                    case .boolean(let item): String(item)
                    case .integer(let item): String(item)
                    case .number(let item): String(item)
                    default: ""
                    }
                }.joined(separator: ", ")
            },
            set: { text in
                guard case .array(let element) = parameter.type else { return }
                let parts = text.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let parsed: [ScenarioValue?] = parts.map { item in
                    switch element {
                    case .primitive(.string): .string(item)
                    case .primitive(.boolean): Bool(item).map(ScenarioValue.boolean)
                    case .primitive(.integer): Int64(item).map(ScenarioValue.integer)
                    case .primitive(.number): Double(item).map(ScenarioValue.number)
                    default: nil
                    }
                }
                guard parsed.allSatisfy({ $0 != nil }) else { return }
                let values = parsed.compactMap { $0 }
                parameter.presence = .value(.array(values))
            }
        )
    }

    private func valueBinding<Value>(
        default defaultValue: Value,
        get: @escaping (ScenarioValue) -> Value?,
        wrap: @escaping (Value) -> ScenarioValue
    ) -> Binding<Value> {
        Binding(
            get: {
                guard case .value(let value) = parameter.presence else { return defaultValue }
                return get(value) ?? defaultValue
            },
            set: { parameter.presence = .value(wrap($0)) }
        )
    }

    private func defaultPresence(for type: ScenarioValueType) -> ScenarioParameterPresence {
        switch type {
        case .primitive(.string): .value(.string(""))
        case .primitive(.boolean): .value(.boolean(false))
        case .primitive(.integer): .value(.integer(0))
        case .primitive(.number): .value(.number(0))
        case .primitive(.date):
            .value(.date(.init(
                source: ISO8601DateFormatter().string(from: Date()),
                timeZoneIdentifier: TimeZone.current.identifier,
                resolvedInstant: Date()
            )))
        case .enumeration(let type, let cases):
            .value(.enumeration(.init(typeIdentifier: type, caseIdentifier: cases.first ?? "case")))
        case .entity(let type): .value(.entity(.init(typeIdentifier: type, identifier: "")))
        case .array: .value(.array([]))
        }
    }
}

private enum ParameterPresenceChoice: Hashable { case missing, value, null }

private struct ScenarioExpectedValueEditor: View {
    @Binding var value: ScenarioValue?

    var body: some View {
        HStack {
            Picker("Expected value type", selection: valueType) {
                Text("None").tag(ExpectedValueType.none)
                Text("Text").tag(ExpectedValueType.string)
                Text("Boolean").tag(ExpectedValueType.boolean)
                Text("Integer").tag(ExpectedValueType.integer)
                Text("Number").tag(ExpectedValueType.number)
            }
            .fixedSize(horizontal: true, vertical: false)
            switch valueType.wrappedValue {
            case .none:
                Text("No deterministic oracle").foregroundStyle(.secondary)
            case .string:
                TextField("Expected text or stable ID", text: stringValue)
            case .boolean:
                Toggle("Expected", isOn: boolValue)
            case .integer:
                TextField("Expected integer", value: integerValue, format: .number)
            case .number:
                TextField("Expected number", value: numberValue, format: .number)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var valueType: Binding<ExpectedValueType> {
        Binding(
            get: {
                switch value {
                case nil: .none
                case .string, .entity, .enumeration, .date, .array, .null: .string
                case .boolean: .boolean
                case .integer: .integer
                case .number: .number
                }
            },
            set: { type in
                switch type {
                case .none: value = nil
                case .string: value = .string("")
                case .boolean: value = .boolean(false)
                case .integer: value = .integer(0)
                case .number: value = .number(0)
                }
            }
        )
    }

    private var stringValue: Binding<String> {
        Binding(
            get: {
                switch value {
                case .string(let item): item
                case .entity(let item): item.identifier
                case .enumeration(let item): item.caseIdentifier
                case .date(let item): item.source
                case .array(let items): "\(items.count) values"
                case .null: "null"
                default: ""
                }
            },
            set: { value = .string($0) }
        )
    }
    private var boolValue: Binding<Bool> { scalar(default: false, get: { if case .boolean(let item) = $0 { item } else { nil } }, wrap: ScenarioValue.boolean) }
    private var integerValue: Binding<Int64> { scalar(default: 0, get: { if case .integer(let item) = $0 { item } else { nil } }, wrap: ScenarioValue.integer) }
    private var numberValue: Binding<Double> { scalar(default: 0, get: { if case .number(let item) = $0 { item } else { nil } }, wrap: ScenarioValue.number) }

    private func scalar<T>(default defaultValue: T, get: @escaping (ScenarioValue) -> T?, wrap: @escaping (T) -> ScenarioValue) -> Binding<T> {
        Binding(get: { value.flatMap(get) ?? defaultValue }, set: { value = wrap($0) })
    }
}

private enum ExpectedValueType: Hashable { case none, string, boolean, integer, number }

private enum ParameterEditorType: String, CaseIterable, Identifiable {
    case string, boolean, integer, number, date, enumeration, entity, array
    var id: Self { self }
    var title: String { rawValue.capitalized }

    init(_ type: ScenarioValueType) {
        switch type {
        case .primitive(.string): self = .string
        case .primitive(.boolean): self = .boolean
        case .primitive(.integer): self = .integer
        case .primitive(.number): self = .number
        case .primitive(.date): self = .date
        case .enumeration: self = .enumeration
        case .entity: self = .entity
        case .array: self = .array
        }
    }

    var valueType: ScenarioValueType {
        switch self {
        case .string: .primitive(.string)
        case .boolean: .primitive(.boolean)
        case .integer: .primitive(.integer)
        case .number: .primitive(.number)
        case .date: .primitive(.date)
        case .enumeration: .enumeration(typeIdentifier: "Enum", allowedCases: ["case"])
        case .entity: .entity(typeIdentifier: "Entity")
        case .array: .array(element: .primitive(.string))
        }
    }
}

private enum ScenarioEditorPage: String, IntentLabEditorPage {
    case outcome, fixture, evidence, parameters, assertions, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .outcome: "Outcome"
        case .fixture: "Intent & fixture"
        case .evidence: "Evidence"
        case .parameters: "Parameters"
        case .assertions: "Assertions"
        case .settings: "Run settings"
        }
    }
    var subtitle: String {
        switch self {
        case .outcome: "Request & expected behavior"
        case .fixture: "Intent definition & test data"
        case .evidence: "Required results for this scenario"
        case .parameters: "Inputs passed to the intent"
        case .assertions: "Observable results & expectations"
        case .settings: "Safety, repetitions & saved versions"
        }
    }
    var symbol: String {
        switch self {
        case .outcome: "text.alignleft"
        case .fixture: "shippingbox"
        case .evidence: "checkmark.shield"
        case .parameters: "curlybraces"
        case .assertions: "checklist"
        case .settings: "slider.horizontal.3"
        }
    }
}
