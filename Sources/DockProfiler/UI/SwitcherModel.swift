import Foundation

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var query: String = "" {
        didSet { clampSelection() }
    }
    @Published var selectedIndex: Int = 0

    private let store = ProfileStore.shared

    var results: [DockProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.profiles }
        return store.profiles
            .compactMap { profile -> (DockProfile, Int)? in
                guard let score = Self.score(profile.name, query: trimmed) else { return nil }
                return (profile, score)
            }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1 ? lhs.offset < rhs.offset : lhs.element.1 > rhs.element.1
            }
            .map(\.element.0)
    }

    var selectedProfile: DockProfile? {
        let results = results
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    func reset() {
        query = ""
        let active = store.activeProfileID
        selectedIndex = store.profiles.firstIndex { $0.id == active } ?? 0
    }

    func moveSelection(by delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func select(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    private func clampSelection() {
        let count = results.count
        if count == 0 {
            selectedIndex = 0
        } else if selectedIndex >= count {
            selectedIndex = count - 1
        }
    }

    /// Prefix beats a word start, which beats a plain match, which beats a
    /// scattered subsequence — enough for a list of a dozen profile names.
    static func score(_ name: String, query: String) -> Int? {
        let haystack = name.lowercased()
        let needle = query.lowercased()

        if haystack.hasPrefix(needle) { return 1000 - haystack.count }
        if let range = haystack.range(of: needle) {
            let distance = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let startsWord = range.lowerBound == haystack.startIndex
                || haystack[haystack.index(before: range.lowerBound)] == " "
            return (startsWord ? 800 : 600) - distance
        }

        // Subsequence: every character of the query, in order.
        var index = haystack.startIndex
        var gaps = 0
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            gaps += haystack.distance(from: index, to: found)
            index = haystack.index(after: found)
        }
        return max(0, 400 - gaps)
    }
}
