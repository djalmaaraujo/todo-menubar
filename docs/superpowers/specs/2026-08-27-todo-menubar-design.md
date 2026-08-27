# Todo Menubar — Design

Native macOS menu bar todo app, modeled on the sibling apps
[`pr-menubar`](https://github.com/djalmaaraujo/pr-menubar) and
[`claude-usage-menubar`](https://github.com/djalmaaraujo/claude-usage-menubar):
Swift/SwiftUI, zero third-party dependencies, compiled with `swiftc`, shipped as a
Homebrew cask. No cloud sync, no search, no preferences window.

## Goal

A menu bar popover to manage simple todos, organized by **workspace** (context).
Create / complete / delete todos. Completing a todo moves it to that workspace's
**History**, a date-grouped timeline. Everything is local.

## Non-goals

- No cloud sync across devices.
- No search.
- No preferences window.
- No tags, due dates, priorities, reminders, or subtasks.
- No un-completing from History (only delete).

## Stack

- Swift 6, SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` + AppKit.
- Target `arm64-apple-macos13.0`, `LSUIElement=true` (menu-bar only, no Dock icon).
- No package.json / Node / SPM / CocoaPods / Xcode project. Build with `swiftc`.
- Ad-hoc code signing (`codesign --force --sign -`).
- Persistence: `UserDefaults.standard` (Codable → JSON `Data`).

## Names & ids

- Repo / cask token / `brew install` slug: `todo-menubar`.
- Display name / `CFBundleName`: **Todo Menubar**.
- Executable + bundle: `TodoMenubar` / `TodoMenubar.app`.
- Bundle id: **`com.djalma.todobar`** (its own id — does not reuse pr-menubar's).

## File layout

```
todo-menubar/
├── app/
│   ├── TodoCore.swift    # Foundation-only: models, TodoStore logic, persistence, grouping
│   ├── App.swift         # @main, MenuBarExtra(.window), all SwiftUI views
│   ├── Tests.swift       # standalone @main test binary over TodoCore
│   ├── build.sh          # swiftc build → TodoMenubar.app, ad-hoc sign, open
│   ├── test.sh           # compile TodoCore + Tests → run assertions
│   ├── make_icon.swift   # generate menubar-mark.png + AppIcon.icns from code
│   ├── Info.plist        # bundle metadata (LSUIElement, bundle id)
│   ├── AppIcon.icns      # generated
│   └── menubar-mark.png  # generated template glyph
├── assets/logo.svg
├── docs/index.html       # GitHub Pages landing, reuses the palette
├── README.md · LICENSE · CLAUDE.md · CLAUDE.local.md · .gitignore
```

Same pure-logic / UI split as pr-menubar: `TodoCore.swift` is Foundation-only so it
links into the test binary without SwiftUI; UI-only concerns (colors, SF Symbols)
are extensions on the core types inside `App.swift`.

## Data model (`TodoCore.swift`)

```swift
struct Workspace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
}

struct Todo: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var workspaceId: UUID
    var done: Bool
    let createdAt: Date
    var completedAt: Date?
}
```

`TodoStore` (an `ObservableObject` in App.swift; the pure logic lives in
`TodoCore.swift` as a plain struct/engine so it is testable without SwiftUI):

- `workspaces: [Workspace]`, `todos: [Todo]`, `selection: Selection` where
  `Selection = .all | .workspace(UUID)`.
- Persistence keys in `UserDefaults.standard`: `"workspaces"`, `"todos"`,
  `"selection"`. Encoded with `JSONEncoder` / decoded with `JSONDecoder`.
- Seed on first run: one workspace named `"Personal"`, selected.

### Operations (pure, tested)

- `addTodo(text, workspaceId)` → appends an active todo (`done=false`,
  `completedAt=nil`) to the end of that workspace's active list.
- `complete(todoId)` → sets `done=true`, `completedAt=now`. Item leaves Active,
  enters History.
- `deleteTodo(todoId)` → removes permanently (works in Active and History).
- `addWorkspace(name)` → appends a workspace; trims/validates non-empty name.
- `renameWorkspace(id, name)` → updates name (non-empty).
- `deleteWorkspace(id)` → removes the workspace **and cascades**: deletes all its
  todos (active + history). If it was the current selection, selection falls back to
  `.all`.
- `activeTodos(for selection)` → active items, ordered by `createdAt` ascending.
  For `.all`, grouped by workspace (see grouping).
- `historyTodos(for selection)` → done items, grouped by completion day, newest day
  first, newest item first within a day.

### Grouping (pure, tested)

- `activeGrouped(selection) -> [(Workspace, [Todo])]` — only used in `.all` mode to
  render workspace headers; workspaces with no active items are omitted; workspace
  order follows `workspaces` array order.
- `historyGrouped(selection) -> [(DayKey, [Todo])]` — `DayKey` is the start-of-day
  `Date` (via `Calendar.current`). Sorted newest day first. The view maps a `DayKey`
  to a label: `Today` / `Yesterday` / `MMM d, yyyy`.

## UI (`App.swift`, popover width 400)

Reuses the sibling palette. Structure top → bottom:

1. **Top bar:** workspace dropdown (`ALL` + each workspace) · **(+)** button opens a
   small sheet with a single text field to name a new workspace · **⋯** menu on the
   current workspace for **Rename** and **Delete** (Delete confirms; disabled/hidden
   when `ALL` or when it's the last workspace's guard is not required — deletion is
   allowed, falling back to ALL).
2. **Tabs:** `Active | History` segmented control, scoped to the current selection.
   Accent indigo on the selected tab.
3. **Content (scroll, maxHeight ~440):**
   - **Active, single workspace:** rows `(○ checkbox)  text  [🗑]`. Checkbox click →
     `complete`. Trash → `deleteTodo`.
   - **Active, ALL:** the same rows under a **workspace header** per group.
   - **History:** date header (`Today` / `Yesterday` / `MMM d, yyyy`) then rows
     `text  [🗑]` (dimmed text). Trash → `deleteTodo`. In ALL, still grouped by day
     across all workspaces.
4. **Bottom input bar** (Active tab only): `[workspace selector] [text field
   "Type a task and hit enter"] [submit ⌤ button, indigo]`.
   - The workspace selector is **pre-filled** with the current workspace when a
     specific one is selected.
   - In **ALL** mode the selector starts unset and the user **must** pick a
     workspace before the submit/Enter is accepted (submit disabled until chosen).

### Colors (reused verbatim from the siblings)

| Token | Hex | Use |
|-------|-----|-----|
| bg start | `#0f172a` | popover / icon gradient start |
| bg end | `#1e1b4b` | icon gradient end |
| accent (indigo) | `#6366f1` | submit button, checkbox check, selected tab, badge |
| accent (cyan) | `#22d3ee` | logo / app-icon gradient |
| accent (sky) | `#38bdf8` | logo / badges |
| text | `#e2e8f0` | primary text |
| text dim | `#94a3b8` | history text, meta, tagline |

`#6366f1` ≈ `Color(red: 0.39, green: 0.40, blue: 0.95)`.

## Menu bar

- Glyph: a checklist mark (checkmark + list lines), generated by `make_icon.swift`
  as a black template PNG (`menubar-mark.png`), loaded with `isTemplate = true`,
  size set directly (no `.resizable()`/`.frame()` — that renders nothing in a
  `MenuBarExtra` label).
- Badge: count of **active** todos in the current selection (current workspace, or
  the total across all workspaces when `ALL`). Hidden when 0.
- On a persistence/decode error the icon swaps to SF Symbol
  `exclamationmark.triangle`.
- Label built as an explicit `HStack { Image; Text }` (the `title:systemImage:`
  initializer drops the title under `.window` style).

## Persistence details

- Encode `workspaces` and `todos` as JSON `Data` under their keys; `selection` as a
  small Codable enum (`{"all": true}` or `{"workspace": "<uuid>"}`) or a string.
- Load at launch; if decode fails, start empty + seed `Personal` and set the error
  flag (menu-bar shows the warning glyph until next successful save).
- Save after every mutation (small dataset, cheap).

## Testing (`Tests.swift`, run by `test.sh`)

Pure-logic assertions over `TodoCore` (no SwiftUI, no UserDefaults side effects —
the engine takes state in and returns new state, persistence is injected):

1. `addTodo` appends an active item to the right workspace, ordered by createdAt.
2. `complete` moves an item out of Active and into History with `completedAt` set.
3. `deleteTodo` removes from Active; and removes from History.
4. `addWorkspace` appends; empty/whitespace name rejected.
5. `renameWorkspace` updates the name; empty rejected.
6. `deleteWorkspace` cascades — its todos (active + done) are gone; selection falls
   back to `.all` when the deleted workspace was selected.
7. `activeGrouped` in ALL groups by workspace, omits empty groups, preserves order.
8. `historyGrouped` groups by day, newest day first, newest item first within a day.
9. Persistence round-trip: encode → decode yields an equal store.
10. `selection` decode fallback: an unknown/dangling workspace id falls back to
    `.all`.

`test.sh` compiles `TodoCore.swift` + `Tests.swift` into a standalone binary and
runs it, exiting non-zero on the first failed assertion.

## Manual verification (before "done")

- `cd app && ./test.sh` green.
- `cd app && swift make_icon.swift` regenerates the glyph + icon.
- `cd app && ./build.sh` builds and launches `TodoMenubar.app`; the menu-bar glyph
  appears. Screenshot the popover: create a workspace, add todos, complete one
  (moves to History), switch to ALL (grouped by workspace), delete a todo from
  History, rename + delete a workspace, quit and relaunch (state persisted).

## Branding & release

- `assets/logo.svg`: wordmark "Todo Menubar" + checklist badge glyph, cyan→indigo
  gradient, same shape as the sibling logos.
- `README.md`: centered logo, centered Pages link, bold tagline
  ("Your todos, right in the menu bar."), shields.io badges
  (`native-swift`, `dependencies-zero`, `license-MIT`), screenshot, then
  What it does / Dependencies / Install / How it works / Privacy / Why / License.
- `docs/index.html`: single-file GitHub Pages landing reusing the CSS-var palette.
- `CLAUDE.md`: build/test/icon commands, names-and-ids block, release checklist
  mirroring pr-menubar (Homebrew cask `Casks/todo-menubar.rb` in the separate
  `homebrew-tap` repo).
- MIT © 2026 Djalma Araújo.
```
```
