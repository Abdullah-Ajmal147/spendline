# Spendline — notes for Claude Code

Flutter expense app. The user types a sentence ("Give to rizwan 1000", "pay for lunch 500"),
the app parses it into structured fields, saves it, and can mirror it to
a local database, with optional Firebase sync and a Google Sheet backup.

## Architecture (v2, local-first)

- The phone is the database: SQLite via `services/store.dart`, loaded into `AppState.entries`. The
  app works with zero setup. Backup = CSV export/restore (`services/csv.dart`) + optional Sheets.
- Firebase sync (`services/firebase_cloud.dart`) uses Firebase Auth + Firestore over REST with the
  Google ID token, so no google-services.json and no native Firebase plugins. Values (Web client ID,
  project ID, Web API key) are pasted in the app (`ui/cloud_setup_screen.dart`, also SETUP_GOOGLE.md).
  Dirty/deleted ids are queued in prefs; pull is "remote wins unless locally dirty". Remote deletions
  are not propagated to other devices yet. Untested against a real Firebase project.
- Filters: `models/filter.dart` + `ui/filter_sheet.dart`, applied to the chat thread via
  `AppState.visibleEntries`.
- Google Sheets is an optional mirror: `services/google_sheets.dart` uses Google Sign-In with the
  `drive.file` scope and plain REST calls. Free, no API key. Needs the OAuth client IDs in
  `lib/config.dart` (steps are in that file). It has NOT been tested against real Google yet.
- Main screen is a chat (`ui/chat_screen.dart`). Each entry's `note` is the sentence the user typed,
  so the thread is rebuilt from entries; nothing else is stored.
- `services/parser.dart` is rules only: Roman Urdu spelling variants are normalised to canonical
  tokens first (`_canon`), then matched. `parseMany` splits "a 500, b 120". Add phrases to
  `test/parser_test.dart` first, then fix the parser.
- Learning: `AppState.learn` stores word -> category after the user corrects a category; the
  parser reads `learnedCategories` and `knownPeople` (multi-word names). Both are globals in parser.dart.
- Voice: `services/voice.dart` (speech_to_text, free on-device recogniser). Default locale ur_PK.
- Person ledger: `ui/person_screen.dart` (balance, WhatsApp reminder via wa.me, Mark settled).
- Groups (Splitwise-style): `models/group.dart` (pure balance + debt-simplification logic, tested),
  `services/group_parser.dart` ("ali ne taxi 800 diya", "pizza 1200 with ali"), `ui/groups_screen.dart`,
  `ui/group_screen.dart`. Single-device only: no sync, groups are not in the Google Sheet. Backup is
  a JSON file next to the CSV. Group expenses do not count in the personal "spent" total yet.
- Theme gives FilledButton an infinite minimumSize width: inside a Row/dialog actions always pass
  `styleFrom(minimumSize: ...)` or it throws a layout assertion.
- `apps_script/` is the old backend and is no longer used.
- Text field has autocorrect off on purpose (keyboards turn "dy" into "money").

## Commands

| Task | Command |
|---|---|
| Install deps | `flutter pub get` (after bumping any flutter_edge_ai package: `flutter pub upgrade`) |
| Lint | `flutter analyze` |
| Tests | `flutter test` |
| Run | `flutter run` |
| Android release | `flutter build apk --release` (or `appbundle`) |
| iOS release | `flutter build ipa` (macOS only) |

## Layout

```
lib/
  main.dart                  app root: splash -> onboarding (once) -> chat
  config.dart                Google/Firebase IDs baked in (Firebase project spendline-8ea2c)
  models/                    entry, group (+balance logic), filter
  services/                  parser, group_parser, store (SQLite), csv, firebase_cloud (REST),
                             google_sheets (Sheets/Drive REST), voice, smart_parser (optional LLM)
  state/app_state.dart       ChangeNotifier: entries, groups, filters, cloud sync queues, summaries
  ui/chat_screen.dart        main screen; entry_editor, filter_sheet, settings_sheet
  ui/home_screen.dart        SummaryScreen (month total, bars, people)
  ui/person_screen.dart      per-person ledger + WhatsApp reminder
  ui/groups_screen.dart, group_screen.dart   Splitwise-style groups
  ui/splash_screen.dart, onboarding_screen.dart
  ui/cloud_setup_screen.dart developer guide to (re)create the Firebase project
assets/icon/                 launcher icon + native splash source (regenerate: see below)
test/                        parser, csv, group, filter/firebase encoding
```

Regenerate icons/splash after changing assets/icon: `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create`.

## Conventions

- State: one `AppState` (ChangeNotifier) passed through constructors, read with
  `ListenableBuilder`. No extra state packages.
- Colors only from `Palette` in `ui/theme.dart`; both light and dark must be updated together.
- Text styles via `display()`, `body()`, `eyebrow()` in `ui/theme.dart`.
- Glass look: wrap surfaces in `Glass(...)`; use `strong: true` for panels holding inputs.
  Keep `BackdropFilter` count low inside scrolling lists (one Glass per section, not per row).
- User-facing errors are plain sentences that say how to fix the problem.
- Any change to parsing rules gets a new case in `test/parser_test.dart`.

## Ideas not built yet

- Daily "log today?" reminder (needs flutter_local_notifications).
- Propagate deletions across devices; invite friends into a group (needs per-group Firestore rules).
- Group expenses in the personal totals; filters inside groups.
- Home-screen quick-add widget.
- Remove flutter_edge_ai to shrink the APK (~95 MB -> ~20 MB) and drop minSdk 30.

## QA notes

- `test/qa_negative_test.dart`: hostile input, boundary values, property fuzzing of the split maths,
  CSV/formula-injection abuse. `test/real_world_test.dart`: 50 realistic Roman Urdu/English sentences;
  failures print as `MISS ...`. Add a sentence there before touching the parser.
- Amounts above `maxAmount` (1e11) and non-finite numbers are never accepted anywhere (parser, CSV).
- Long lists use `ListView.builder` + `Glass.flat` (no blur). Never build every entry up front.
- Saved Settings values that are blank fall back to the built-in config, never to "not configured".
