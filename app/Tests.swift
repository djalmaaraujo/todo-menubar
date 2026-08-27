import Foundation

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message) (line \(line))\n".utf8))
    }
}

let day0 = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ offset: TimeInterval) -> Date { day0.addingTimeInterval(offset) }

let wsA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
let wsB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
let t1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let t2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let t3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

func baseState() -> TodoState {
    var s = TodoState()
    _ = s.addWorkspace("Work", id: wsA, now: at(0))
    _ = s.addWorkspace("Home", id: wsB, now: at(1))
    return s
}

@main
enum TestRunner {
    static func main() {
        run()
        if failures == 0 {
            print("ok — \(checks) checks passed")
            exit(0)
        } else {
            FileHandle.standardError.write(Data("\(failures)/\(checks) checks FAILED\n".utf8))
            exit(1)
        }
    }

    static func run() {

do {
    var s = baseState()
    check(s.addTodo("first", to: wsA, id: t1, now: at(10)), "addTodo returns true")
    check(s.addTodo("second", to: wsA, id: t2, now: at(20)), "addTodo second returns true")
    let active = s.activeTodos(for: .workspace(wsA))
    check(active.map(\.text) == ["first", "second"], "active ordered by createdAt asc")
    check(active.allSatisfy { !$0.done }, "new todos are active")
}

do {
    var s = baseState()
    check(!s.addTodo("   ", to: wsA), "empty/whitespace text rejected")
    check(!s.addTodo("x", to: UUID()), "unknown workspace rejected")
    check(s.todos.isEmpty, "nothing added on rejection")
}

do {
    var s = baseState()
    _ = s.addTodo("do it", to: wsA, id: t1, now: at(10))
    s.complete(t1, now: at(30))
    check(s.activeTodos(for: .workspace(wsA)).isEmpty, "completed item left Active")
    let hist = s.historyGrouped(for: .workspace(wsA))
    check(hist.flatMap(\.todos).map(\.id) == [t1], "completed item entered History")
    check(hist.flatMap(\.todos).first?.completedAt == at(30), "completedAt set")
}

do {
    var s = baseState()
    _ = s.addTodo("a", to: wsA, id: t1, now: at(10))
    s.deleteTodo(t1)
    check(s.todos.isEmpty, "deleted from Active")

    _ = s.addTodo("b", to: wsA, id: t2, now: at(11))
    s.complete(t2, now: at(40))
    s.deleteTodo(t2)
    check(s.todos.isEmpty, "deleted from History")
}

do {
    var s = TodoState()
    check(s.addWorkspace("Alpha", now: at(0)) != nil, "addWorkspace returns workspace")
    check(s.addWorkspace("   ", now: at(1)) == nil, "empty workspace rejected")
    check(s.workspaces.count == 1, "only valid workspace added")
}

do {
    var s = baseState()
    check(s.renameWorkspace(wsA, to: "Renamed"), "rename returns true")
    check(s.workspace(wsA)?.name == "Renamed", "name updated")
    check(!s.renameWorkspace(wsA, to: "  "), "empty rename rejected")
    check(s.workspace(wsA)?.name == "Renamed", "name unchanged after rejected rename")
}

do {
    var s = baseState()
    _ = s.addTodo("keep", to: wsB, id: t1, now: at(10))
    _ = s.addTodo("gone", to: wsA, id: t2, now: at(11))
    s.complete(t2, now: at(20))
    s.selection = .workspace(wsA)
    s.deleteWorkspace(wsA)
    check(s.workspace(wsA) == nil, "workspace removed")
    check(s.todos.map(\.id) == [t1], "workspace todos (active + done) cascaded")
    check(s.selection == .all, "selection fell back to .all")
}

do {
    var s = baseState()
    _ = s.addWorkspace("Empty", id: UUID(), now: at(2))
    _ = s.addTodo("h1", to: wsB, id: t1, now: at(10))
    _ = s.addTodo("w1", to: wsA, id: t2, now: at(11))
    let groups = s.activeGrouped(for: .all)
    check(groups.map(\.workspace.id) == [wsA, wsB], "groups follow workspace order, empty omitted")
    check(groups.first?.todos.map(\.text) == ["w1"], "group A items")
}

do {
    var s = baseState()
    let cal = Calendar(identifier: .gregorian)
    let dayA = Date(timeIntervalSince1970: 1_700_000_000)
    let dayB = dayA.addingTimeInterval(48 * 3600)
    _ = s.addTodo("older-day", to: wsA, id: t1, now: dayA)
    _ = s.addTodo("newer-day-early", to: wsA, id: t2, now: dayB)
    _ = s.addTodo("newer-day-late", to: wsA, id: t3, now: dayB)
    s.complete(t1, now: dayA)
    s.complete(t2, now: dayB.addingTimeInterval(60))
    s.complete(t3, now: dayB.addingTimeInterval(120))
    let hist = s.historyGrouped(for: .workspace(wsA), calendar: cal)
    check(hist.count == 2, "two day groups")
    check(hist.first?.todos.map(\.id) == [t3, t2], "newest day first, newest item first")
    check(hist.last?.todos.map(\.id) == [t1], "older day last")
}

do {
    var s = baseState()
    _ = s.addTodo("persist me", to: wsA, id: t1, now: at(10))
    s.complete(t1, now: at(20))
    s.selection = .workspace(wsB)
    let data = try! JSONEncoder().encode(s)
    let back = try! JSONDecoder().decode(TodoState.self, from: data)
    check(back == s, "encode → decode yields an equal store")
}

do {
    var s = baseState()
    s.selection = .workspace(UUID())
    s.normalizeSelection()
    check(s.selection == .all, "dangling selection normalized to .all")

    s.selection = .workspace(wsA)
    s.normalizeSelection()
    check(s.selection == .workspace(wsA), "valid selection preserved")
}

do {
    var s = baseState()
    _ = s.addTodo("a", to: wsA, id: t1, now: at(10))
    _ = s.addTodo("b", to: wsB, id: t2, now: at(11))
    _ = s.addTodo("c", to: wsB, id: t3, now: at(12))
    s.complete(t1, now: at(20))
    check(s.activeCount(for: .all) == 2, "ALL active count excludes done")
    check(s.activeCount(for: .workspace(wsB)) == 2, "workspace active count")
    check(s.activeCount(for: .workspace(wsA)) == 0, "completed leaves count")
}

    }
}
