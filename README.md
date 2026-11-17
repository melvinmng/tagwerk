# Tagwerk

Private iOS app that brings Apple Reminders, GitHub issues and the calendar into one place, with an AI day planner and tracking for nutrition and training.

Status: Phase 2 in progress. Design and plans live in `docs/superpowers/`.

## Layout

- `app/` – the iOS app (XcodeGen, `app/project.yml`; the generated `.xcodeproj` is not checked in)
  - `app/Tagwerk/` – SwiftUI app target (task list, editor, setup, settings, SwiftData persistence)
  - `app/Packages/TagwerkCore` – task model, sections and date logic (Foundation only)
  - `app/Packages/RemindersKit` – EventKit access with conflict-checked writes
  - `app/Packages/SecureStore` – keychain storage
- `scripts/` – build and install helpers, see `scripts/README.md`
- `spike/` – Phase 1 feasibility app (reference only, removed after the switch)

## Development

Requirements: Xcode 27.2, XcodeGen 2.46, simulator "iPhone 18 Pro".

```zsh
app/test-all.sh          # all package tests and the app tests in the simulator
scripts/install-dev.sh   # build the working tree and install it on the iPhone
```

Both scripts set `DEVELOPER_DIR` themselves. The device identifier is read from `~/Library/Application Support/Tagwerk/config` and never stored in the repository.
