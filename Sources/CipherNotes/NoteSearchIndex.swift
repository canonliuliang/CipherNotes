import Foundation

@MainActor
final class NoteSearchIndex: ObservableObject {
    @Published var query = "" {
        didSet { scheduleQueryUpdate() }
    }
    @Published private(set) var effectiveQuery = ""

    private struct Entry {
        let updatedAt: Date
        let searchableText: String
    }
    private var entries: [UUID: Entry] = [:]
    private var updateTask: Task<Void, Never>?

    func matches(_ note: Note) -> Bool {
        let needle = normalized(effectiveQuery)
        guard !needle.isEmpty else { return true }
        let entry: Entry
        if let cached = entries[note.id], cached.updatedAt == note.updatedAt {
            entry = cached
        } else {
            entry = Entry(
                updatedAt: note.updatedAt,
                searchableText: normalized(([note.title, note.body] + note.tags).joined(separator: "\n"))
            )
            entries[note.id] = entry
        }
        return entry.searchableText.contains(needle)
    }

    private func scheduleQueryUpdate() {
        updateTask?.cancel()
        let pending = query
        updateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            effectiveQuery = pending
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
