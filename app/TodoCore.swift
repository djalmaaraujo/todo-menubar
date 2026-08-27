import Foundation

struct Workspace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct Todo: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var workspaceId: UUID
    var done: Bool
    let createdAt: Date
    var completedAt: Date?

    init(id: UUID = UUID(), text: String, workspaceId: UUID, done: Bool = false,
         createdAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.workspaceId = workspaceId
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

enum Selection: Codable, Equatable {
    case all
    case workspace(UUID)
}

struct TodoState: Codable, Equatable {
    var workspaces: [Workspace]
    var todos: [Todo]
    var selection: Selection

    init(workspaces: [Workspace] = [], todos: [Todo] = [], selection: Selection = .all) {
        self.workspaces = workspaces
        self.todos = todos
        self.selection = selection
    }

    static func seeded(now: Date = Date()) -> TodoState {
        let personal = Workspace(name: "Personal", createdAt: now)
        return TodoState(workspaces: [personal], todos: [], selection: .workspace(personal.id))
    }
}

extension TodoState {
    static func todoLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { stripBullet($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    private static func stripBullet(_ line: String) -> String {
        for marker in ["- ", "* ", "• ", "– ", "— "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    func workspace(_ id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    @discardableResult
    mutating func addTodo(_ text: String, to workspaceId: UUID, id: UUID = UUID(),
                          now: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, workspace(workspaceId) != nil else { return false }
        todos.append(Todo(id: id, text: trimmed, workspaceId: workspaceId, createdAt: now))
        return true
    }

    mutating func complete(_ todoId: UUID, now: Date = Date()) {
        guard let i = todos.firstIndex(where: { $0.id == todoId }) else { return }
        todos[i].done = true
        todos[i].completedAt = now
    }

    mutating func deleteTodo(_ todoId: UUID) {
        todos.removeAll { $0.id == todoId }
    }

    @discardableResult
    mutating func addWorkspace(_ name: String, id: UUID = UUID(), now: Date = Date()) -> Workspace? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ws = Workspace(id: id, name: trimmed, createdAt: now)
        workspaces.append(ws)
        return ws
    }

    @discardableResult
    mutating func renameWorkspace(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = workspaces.firstIndex(where: { $0.id == id }) else {
            return false
        }
        workspaces[i].name = trimmed
        return true
    }

    mutating func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        todos.removeAll { $0.workspaceId == id }
        if selection == .workspace(id) { selection = .all }
    }

    mutating func normalizeSelection() {
        if case .workspace(let id) = selection, workspace(id) == nil {
            selection = .all
        }
    }
}

extension TodoState {
    private func matches(_ todo: Todo, _ selection: Selection) -> Bool {
        switch selection {
        case .all: return true
        case .workspace(let id): return todo.workspaceId == id
        }
    }

    func activeTodos(for selection: Selection) -> [Todo] {
        todos.filter { !$0.done && matches($0, selection) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func activeCount(for selection: Selection) -> Int {
        todos.reduce(0) { $0 + (!$1.done && matches($1, selection) ? 1 : 0) }
    }

    func activeGrouped(for selection: Selection) -> [(workspace: Workspace, todos: [Todo])] {
        let active = activeTodos(for: selection)
        var groups: [(Workspace, [Todo])] = []
        for ws in workspaces {
            let items = active.filter { $0.workspaceId == ws.id }
            if !items.isEmpty { groups.append((ws, items)) }
        }
        return groups
    }

    func historyGrouped(for selection: Selection,
                        calendar: Calendar = .current) -> [(day: Date, todos: [Todo])] {
        let done = todos.filter { $0.done && matches($0, selection) }
        var buckets: [Date: [Todo]] = [:]
        for todo in done {
            let day = calendar.startOfDay(for: todo.completedAt ?? todo.createdAt)
            buckets[day, default: []].append(todo)
        }
        return buckets
            .map { day, items in
                (day: day, todos: items.sorted {
                    ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
                })
            }
            .sorted { $0.day > $1.day }
    }
}
