# Tagwerk

Private iOS app that brings Apple Reminders, GitHub issues and the calendar into one place, with an AI day planner and tracking for nutrition and training.

Status: Phase 2 in progress. Design and plans live in `docs/superpowers/`.

## Layout

- `app/` – the iOS app (XcodeGen, `app/project.yml`; the generated `.xcodeproj` is not checked in)
  - `app/Tagwerk/` – SwiftUI app target (planning, task list, editor, setup, settings, SwiftData persistence)
  - `app/Packages/TagwerkCore` – task model, sections and date logic (Foundation only)
  - `app/Packages/RemindersKit` – EventKit access with conflict-checked writes
  - `app/Packages/SecureStore` – keychain storage
  - `app/Packages/GitHubKit` – GitHub device-flow login, token refresh, Projects (GraphQL) and Issues (REST)
- `scripts/` – build and install helpers, see `scripts/README.md`
- `spike/` – Phase 1 feasibility app (reference only, removed after the switch)

## Development

Requirements: Xcode 27.2, XcodeGen 2.46, simulator "iPhone 18 Pro".

```zsh
app/test-all.sh          # all package tests and the app tests in the simulator
scripts/install-dev.sh   # build the working tree and install it on the iPhone
```

Both scripts set `DEVELOPER_DIR` themselves. The device identifier is read from `~/Library/Application Support/Tagwerk/config` and never stored in the repository.

## GitHub

Sign in under Settings → GitHub or during setup ("Mit GitHub anmelden"). Tagwerk uses the OAuth app "Tagwerk" with the device flow: the app shows a code, you enter it at github.com/login/device. Requested scopes: `repo project offline_access`. There is no client secret; the client ID lives in `app/Config/GitHub.xcconfig`.

- Tokens are stored in the keychain (this device only). The access token expires after 8 hours and is renewed automatically with the refresh token; an unused sign-in expires after about 6 months.
- Signing out deletes the tokens and the cached issues on the device. To revoke access completely: github.com → Settings → Applications → Authorized OAuth Apps → Tagwerk.
- Read: all open GitHub Projects of your account; shown are open issues assigned to you whose project status is not "Done". Fields are matched by name: Status, Priority (P1–P5), Due date, Estimate (h) or Estimate (MDs, 8 h per day).
- Write: title, description, labels, comments, close/reopen (REST); Due date, Priority, Estimate and Status (GraphQL). "Done" closes the issue first and then sets the status in every project. New issues are assigned to you and added to the chosen project with status "Ready".
- Before every write the issue is reloaded; if it changed meanwhile, the editor offers "Neu laden" or "Trotzdem sichern".
- Offline, the list shows the last fetched state ("Stand: hh:mm, offline") and writing is disabled.

## Planning

The "Planen" tab shows a day, a week or a month. Tasks are planned for a day (stored in Tagwerk only; the due date in Reminders or GitHub is not changed) by dragging them onto a day or with the long-press menu ("Einplanen: Heute / Morgen / Wochenende / Nächste Woche").

- Capacity per day = working hours of that weekday (or a different value for that date) − events (with buffer) − lunch − recurring effort. Tasks without effort count with the default duration.
- Important deadlines: P1 tasks, GitHub epics (label `epic`, via sub-issues) and events from deadline calendars.
- Time blocks are written as events into the plan calendar ("Tagwerk"), with `tagwerk://task/…` in the URL field. Events whose title contains `#<number>` of an assigned issue, or exactly matches a reminder, are linked automatically; links can also be set by hand.
- Recurring reminders (e.g. daily flash cards) can carry an effort that reserves time on each occurrence, editable for one day or from a day on.
