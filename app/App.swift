import SwiftUI
import AppKit
import Combine

extension Color {
    static let accentIndigo = Color(red: 0.39, green: 0.40, blue: 0.95)   // #6366f1
    static let textMain     = Color(red: 0.886, green: 0.910, blue: 0.941) // #e2e8f0
    static let textDim      = Color(red: 0.58, green: 0.64, blue: 0.72)    // #94a3b8
}

final class TodoStore: ObservableObject {
    @Published private(set) var state: TodoState
    @Published var errorText: String?

    private let defaults: UserDefaults
    private let key = "todostate.v1"
    private let backupKey = "todostate.v1.unreadable-backup"
    private let readErrorText = "Could not read saved todos (a backup was kept)"
    private let saveErrorText = "Could not save todos"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do {
                var loaded = try JSONDecoder().decode(TodoState.self, from: data)
                loaded.normalizeSelection()
                state = loaded
            } catch {
                defaults.set(data, forKey: backupKey)
                state = .seeded()
                errorText = readErrorText
            }
        } else {
            state = .seeded()
        }
    }

    func select(_ selection: Selection) { mutate { $0.selection = selection } }
    func addTodo(_ text: String, to workspaceId: UUID) { mutate { _ = $0.addTodo(text, to: workspaceId) } }
    func complete(_ id: UUID) { mutate { $0.complete(id) } }
    func deleteTodo(_ id: UUID) { mutate { $0.deleteTodo(id) } }
    func renameWorkspace(_ id: UUID, to name: String) { mutate { _ = $0.renameWorkspace(id, to: name) } }
    func deleteWorkspace(_ id: UUID) { mutate { $0.deleteWorkspace(id) } }

    @discardableResult
    func addWorkspace(_ name: String) -> Workspace? {
        var created: Workspace?
        mutate { created = $0.addWorkspace(name) }
        return created
    }

    private func mutate(_ block: (inout TodoState) -> Void) {
        var next = state
        block(&next)
        state = next
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: key)
            if errorText == saveErrorText { errorText = nil }
        } catch {
            errorText = saveErrorText
        }
    }
}

enum MenuBarMark {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "menubar-mark", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            let height: CGFloat = 16
            let ratio = img.size.width / max(img.size.height, 1)
            img.size = NSSize(width: height * ratio, height: height)
            return img
        }
        let fallback = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todos")
            ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }()
}

#if !RENDER
@main
struct TodoMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TodoStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var cancellables: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: ContentView(store: store))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        store.$state.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshButton() }.store(in: &cancellables)
        store.$errorText.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshButton() }.store(in: &cancellables)
        refreshButton()
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        if store.errorText != nil {
            let warning = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            warning?.isTemplate = true
            button.image = warning
            button.title = ""
        } else {
            button.image = MenuBarMark.image
            let count = store.state.activeCount(for: store.state.selection)
            button.title = count > 0 ? " \(count)" : ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
#endif

enum Tab: Hashable { case active, history }

private enum Overlay: Identifiable {
    case newWorkspace
    case rename(Workspace)
    case deleteConfirm(Workspace)

    var id: String {
        switch self {
        case .newWorkspace: return "new"
        case .rename(let w): return "rename-\(w.id)"
        case .deleteConfirm(let w): return "delete-\(w.id)"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: TodoStore

    @State private var tab: Tab
    @State private var input = ""
    @State private var overlay: Overlay?
    @State private var overlayText = ""

    init(store: TodoStore, initialTab: Tab = .active) {
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Active").tag(Tab.active)
                    Text("History").tag(Tab.history)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
                Divider()
                content
                Divider()
                bottomBar
            }
            .disabled(overlay != nil)
            .blur(radius: overlay != nil ? 2 : 0)

            if overlay != nil { overlayCard }
        }
        .frame(width: 400)
        .tint(.accentIndigo)
    }

    private func selectionRow(_ name: String, isOn: Bool) -> some View {
        HStack {
            Text(name)
            if isOn { Image(systemName: "checkmark") }
        }
    }

    private var currentTitle: String {
        switch store.state.selection {
        case .all: return "All"
        case .workspace(let id): return store.state.workspace(id)?.name ?? "All"
        }
    }


    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if tab == .active { activeContent } else { historyContent }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .frame(height: 300)
    }

    @ViewBuilder
    private var activeContent: some View {
        if store.state.selection == .all {
            let groups = store.state.activeGrouped(for: .all)
            if groups.isEmpty {
                emptyState("No tasks yet")
            } else {
                ForEach(groups, id: \.workspace.id) { group in
                    sectionHeader(group.workspace.name)
                    ForEach(group.todos) { todo in activeRow(todo) }
                }
            }
        } else {
            let items = store.state.activeTodos(for: store.state.selection)
            if items.isEmpty {
                emptyState("No tasks yet")
            } else {
                ForEach(items) { todo in activeRow(todo) }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        let groups = store.state.historyGrouped(for: store.state.selection)
        if groups.isEmpty {
            emptyState("Nothing completed yet")
        } else {
            ForEach(groups, id: \.day) { group in
                sectionHeader(dayLabel(group.day))
                ForEach(group.todos) { todo in historyRow(todo) }
            }
        }
    }

    private func activeRow(_ todo: Todo) -> some View {
        HStack(spacing: 11) {
            Button { store.complete(todo.id) } label: {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text(todo.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textMain)

            Spacer(minLength: 8)

            trashButton(todo)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
    }

    private func historyRow(_ todo: Todo) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentIndigo.opacity(0.8))
            Text(todo.text)
                .font(.system(size: 13))
                .foregroundStyle(Color.textDim)
                .strikethrough(true, color: Color.textDim.opacity(0.6))
            if store.state.selection == .all, let ws = store.state.workspace(todo.workspaceId) {
                Text(ws.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentIndigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentIndigo.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 8)
            trashButton(todo)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
    }

    private func trashButton(_ todo: Todo) -> some View {
        Button { store.deleteTodo(todo.id) } label: {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.textDim)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func emptyState(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 40)
    }


    private var bottomBar: some View {
        HStack(spacing: 8) {
            workspaceMenu
            TextField(inputPlaceholder, text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(submit)
                .disabled(effectiveTarget == nil)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 24)
                    .background(canSubmit ? Color.accentIndigo : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var workspaceMenu: some View {
        Menu {
            Button { store.select(.all) } label: { selectionRow("All", isOn: store.state.selection == .all) }
            if !store.state.workspaces.isEmpty { Divider() }
            ForEach(store.state.workspaces) { ws in
                Button { store.select(.workspace(ws.id)) } label: {
                    selectionRow(ws.name, isOn: store.state.selection == .workspace(ws.id))
                }
            }
            Divider()
            Button { overlayText = ""; overlay = .newWorkspace } label: {
                Label("New workspace…", systemImage: "plus")
            }
            if case .workspace(let id) = store.state.selection, let ws = store.state.workspace(id) {
                Button { overlayText = ws.name; overlay = .rename(ws) } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button(role: .destructive) { overlay = .deleteConfirm(ws) } label: {
                    Label("Delete…", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray.full").font(.system(size: 11))
                Text(currentTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color.accentIndigo)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var effectiveTarget: UUID? {
        if case .workspace(let id) = store.state.selection { return id }
        return nil
    }

    private var inputPlaceholder: String {
        effectiveTarget == nil ? "Pick a workspace to add" : "Type a task and hit enter"
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && effectiveTarget != nil
    }

    private func submit() {
        guard canSubmit, let target = effectiveTarget else { return }
        store.addTodo(input, to: target)
        input = ""
    }


    @ViewBuilder
    private var overlayCard: some View {
        Color.black.opacity(0.35).ignoresSafeArea()
            .onTapGesture { overlay = nil }

        VStack(spacing: 14) {
            switch overlay {
            case .newWorkspace:
                overlayTitle("New workspace")
                overlayField("Workspace name")
                overlayButtons(confirm: "Create", role: .plain)
            case .rename:
                overlayTitle("Rename workspace")
                overlayField("Workspace name")
                overlayButtons(confirm: "Save", role: .plain)
            case .deleteConfirm(let ws):
                overlayTitle("Delete “\(ws.name)”?")
                Text("This removes the workspace and all its tasks and history.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                overlayButtons(confirm: "Delete", role: .destructive)
            case .none:
                EmptyView()
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
        .shadow(radius: 20)
    }

    private func overlayTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .bold)).multilineTextAlignment(.center)
    }

    private func overlayField(_ placeholder: String) -> some View {
        TextField(placeholder, text: $overlayText)
            .textFieldStyle(.roundedBorder)
            .onSubmit { confirmOverlay() }
    }

    private enum OverlayRole { case plain, destructive }

    private func overlayButtons(confirm: String, role: OverlayRole) -> some View {
        HStack(spacing: 10) {
            Button("Cancel") { overlay = nil }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(confirm) { confirmOverlay() }
                .keyboardShortcut(.defaultAction)
                .tint(role == .destructive ? .red : .accentIndigo)
                .buttonStyle(.borderedProminent)
        }
    }

    private func confirmOverlay() {
        switch overlay {
        case .newWorkspace:
            if let ws = store.addWorkspace(overlayText) { store.select(.workspace(ws.id)) }
        case .rename(let ws):
            store.renameWorkspace(ws.id, to: overlayText)
        case .deleteConfirm(let ws):
            store.deleteWorkspace(ws.id)
        case .none:
            break
        }
        overlay = nil
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: day)
    }
}

#if RENDER
func makeSampleStore(selectAll: Bool = false) -> TodoStore {
    let suite = UserDefaults(suiteName: "todobar.preview")!
    suite.removePersistentDomain(forName: "todobar.preview")
    let store = TodoStore(defaults: suite)
    let personal = store.state.workspaces.first!
    store.renameWorkspace(personal.id, to: "Personal")
    let work = store.addWorkspace("Work")!
    store.addTodo("Buy milk", to: personal.id)
    store.addTodo("Pay bills", to: personal.id)
    store.addTodo("Water plants", to: personal.id)
    store.addTodo("Buy birthday gift", to: personal.id)
    store.addTodo("Ship the release", to: work.id)
    store.addTodo("Review the PR", to: work.id)
    store.addTodo("Walk the dog", to: personal.id)
    for done in ["Walk the dog", "Review the PR"] {
        if let t = store.state.todos.first(where: { $0.text == done }) { store.complete(t.id) }
    }
    store.select(selectAll ? .all : .workspace(personal.id))
    return store
}

@main
enum RenderMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let env = ProcessInfo.processInfo.environment
        let mode = env["RENDER_MODE"] ?? "active"
        let out = env["RENDER_OUT"] ?? "render.png"

        let store: TodoStore
        let tab: Tab
        switch mode {
        case "all":     store = makeSampleStore(selectAll: true);  tab = .active
        case "history": store = makeSampleStore(selectAll: true);  tab = .history
        default:        store = makeSampleStore(selectAll: false); tab = .active
        }

        let size = NSSize(width: 400, height: 560)
        let host = NSHostingView(rootView:
            ZStack {
                Color(red: 0.114, green: 0.125, blue: 0.153)
                ContentView(store: store, initialTab: tab)
            }
            .frame(width: size.width, height: size.height)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderFront(nil)

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
                FileHandle.standardError.write(Data("rendered \(out) (\(mode))\n".utf8))
            }
        } else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
        }
        exit(0)
    }
}
#endif
