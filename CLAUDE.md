# CLAUDE.md — Todo Menubar

Native macOS menu bar todo list, organized by workspace. Single build, no Xcode
project: `app/build.sh` compiles `app/TodoCore.swift` + `app/App.swift` with
`swiftc` into `TodoMenubar.app`, ad-hoc signed. Data lives in `UserDefaults`.

- **Test:** `cd app && ./test.sh` (pure logic in `TodoCore.swift`, run as a standalone binary).
- **Build + run:** `cd app && ./build.sh`.
- **Regenerate icons:** `cd app && swift make_icon.swift` (writes `menubar-mark.png` + `AppIcon.icns`).

## Architecture

- `TodoCore.swift` — Foundation-only. `Workspace`, `Todo`, `Selection`, and
  `TodoState` with every operation as a pure `mutating` func plus the grouping
  queries. This is what the tests exercise; keep it free of SwiftUI/UserDefaults.
- `App.swift` — SwiftUI + AppKit. `TodoStore` (the `ObservableObject` that owns a
  `TodoState` and persists it), an `AppDelegate` that runs the menu bar
  (`NSStatusItem` + `NSPopover`), and all the views.
- Persistence: one JSON blob under the `UserDefaults` key `todostate.v1`. Saved
  after every mutation; loaded (and `normalizeSelection()`'d) at launch.

The bottom bar's workspace selector is the only place to switch selection (there
is no top dropdown) and it also carries New / Rename / Delete workspace. Adding a
task is disabled while `All` is selected — pick a specific workspace first.

## Rendering the UI headlessly

Screenshots can't be taken here (no Screen Recording / accessibility), so `App.swift`
carries a `#if RENDER` entry point that draws `ContentView` into a PNG via
`NSHostingView.cacheDisplay` — real fonts and SF Symbols, no window, no screen
capture. It's compiled out of the shipped app (guarded by the `RENDER` flag;
`build.sh` never sets it). To regenerate the README shots:

```sh
cd app
swiftc -parse-as-library -DRENDER -O -o build/render TodoCore.swift App.swift \
    -framework SwiftUI -framework AppKit -target arm64-apple-macos13.0
RENDER_MODE=active  RENDER_OUT=../assets/screenshot-main.png    ./build/render
RENDER_MODE=all     RENDER_OUT=../assets/screenshot-all.png     ./build/render
RENDER_MODE=history RENDER_OUT=../assets/screenshot-history.png ./build/render
```

## Names and ids

- Repo, cask token, `brew install` slug: `todo-menubar`.
- Display name / `CFBundleName`: **Todo Menubar**.
- Executable + bundle: `TodoMenubar` / `TodoMenubar.app`.
- **Bundle id: `com.djalma.todobar`.** The `UserDefaults` store and the cask's
  `zap` plist follow this id. Changing it orphans everyone's saved todos.

## Release checklist

Ships as a Homebrew cask in a **separate repo**:
`git@github.com:djalmaaraujo/homebrew-tap.git`, file `Casks/todo-menubar.rb`. A
GitHub release here is not enough on its own — the cask pins an exact `version` +
`sha256`, so it keeps serving the old build until that file is updated too. Every
release needs both halves.

1. Bump `CFBundleShortVersionString` in `app/Info.plist`, then build clean and zip:
   `cd app; ./build.sh; cd build; ditto -c -k --sequesterRsrc --keepParent TodoMenubar.app TodoMenubar.app.zip; shasum -a 256 TodoMenubar.app.zip`
2. Tag + push, then create the GitHub release with that zip attached:
   `gh release create vX.Y.Z app/build/TodoMenubar.app.zip --title vX.Y.Z --notes "..."`
3. **Update the tap** — clone/pull `homebrew-tap`, edit `Casks/todo-menubar.rb`:
   `version`, `sha256`, and the `vX.Y.Z` in the `url`. Commit + push there too.
4. Verify end to end:
   `brew update; brew upgrade --cask todo-menubar; defaults read /Applications/TodoMenubar.app/Contents/Info.plist CFBundleShortVersionString`.

Skipping step 3 is the most likely mistake — the GitHub release succeeding gives no
signal that the tap is still stale.

## Gotchas learned the hard way

- **Never force-push the tap.** Only ADD commits to `homebrew-tap`. Amending/rebasing
  after push corrupts every consumer's clone.
- **The arrow/tail pointing at the menu-bar icon comes from `NSPopover`.**
  `MenuBarExtra(.window)` draws a plain panel with no arrow — that's why the shell is
  a manual `NSStatusItem` + `NSPopover` (`.transient`, anchored to the status button
  with `preferredEdge: .minY`), not `MenuBarExtra`.
- **Menu bar icon: set `NSImage.size` directly** (aspect-preserving), template on —
  don't rely on autosizing. The badge is `statusItem.button.title` (a plain `String`,
  so no SwiftUI `LocalizedStringKey` thousands-separator issue).
- **Sheets/`confirmationDialog` are unreliable inside the popover.**
  New/rename/delete-workspace are drawn as an in-popover overlay card, not a sheet.
- **The badge updates via Combine** — `AppDelegate` sinks `store.$state`/`$errorText`
  on `RunLoop.main` (so it reads the post-change value) and refreshes the button.
- **`Tests.swift` needs `@main` + `-parse-as-library`.** Top-level statements are
  rejected by `-parse-as-library`; the whole suite runs inside `TestRunner.main()`.
