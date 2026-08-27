# CLAUDE.local.md — Todo Menubar (per-repo overrides)

Sits on top of the base `~/dev/CLAUDE.md`. Only the deltas for this repo.

## Audience / language

Public repo. **Everything outside the chat is English** — README, PR, issue,
comment, commit, docs. Chat with Djalma stays Portuguese (base rule).

## Git

- Branch prefix: `da-` (base default).
- Conventional Commits, one line, signed, authored as Djalma. Never `Co-Authored-By`,
  never any AI attribution.

## This repo's commands

- **Test:** `cd app && ./test.sh`
- **Build + run (menu bar):** `cd app && ./build.sh`
- **Regenerate icons:** `cd app && swift make_icon.swift`
- **Regenerate README screenshots (headless):** see the `#if RENDER` block in
  `CLAUDE.md` — `swiftc -DRENDER … && RENDER_MODE=active|all|history ./build/render`.

## Verifying UI changes

No Screen Recording / accessibility here, so the live menu-bar popover can't be
screenshotted. Verify with `./test.sh` (logic) + the `-DRENDER` PNG dump (visuals).
`./build.sh` confirms the real menu-bar target compiles and launches.
