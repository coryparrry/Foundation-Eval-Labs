import Testing
@testable import FoundationEvals

struct AccessibilitySelectionActionsTests {
    private struct Option: Hashable {
        let id: Int
        let title: String
    }

    @Test func disambiguatesDuplicateAndBlankTitles() {
        let options = [
            Option(id: 1, title: "Shared"),
            Option(id: 2, title: "Shared"),
            Option(id: 3, title: ""),
            Option(id: 4, title: "  \n")
        ]

        let actions = SelectionActionDescriptor.make(options: options, title: \.title)

        #expect(actions.map(\.label) == [
            "Select Shared",
            "Select Shared (1)",
            "Select Untitled option",
            "Select Untitled option (1)"
        ])
    }

    @Test func deduplicatesEqualValuesWithoutReorderingFirstOccurrences() {
        let first = Option(id: 1, title: "First")
        let second = Option(id: 2, title: "Second")
        let third = Option(id: 3, title: "Third")

        let actions = SelectionActionDescriptor.make(
            options: [second, first, second, third, first],
            title: \.title
        )

        #expect(actions.map(\.option) == [second, first, third])
        #expect(actions.map(\.label) == ["Select Second", "Select First", "Select Third"])
    }

    @Test func generatedSuffixesDoNotCollideWithLiteralTitles() {
        let options = [
            Option(id: 1, title: "A"),
            Option(id: 2, title: "A"),
            Option(id: 3, title: "A (1)"),
            Option(id: 4, title: "A"),
            Option(id: 5, title: "Unique")
        ]

        let actions = SelectionActionDescriptor.make(options: options, title: \.title)

        #expect(actions.map(\.label) == [
            "Select A",
            "Select A (2)",
            "Select A (1)",
            "Select A (3)",
            "Select Unique"
        ])
        #expect(Set(actions.map(\.label)).count == actions.count)
    }
}
