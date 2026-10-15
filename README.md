# Spendline

Chat-style expense tracker for Android (Flutter). Type or say "lunch 500", "mainy 500 rizwan ko dy ha" or
"ali se 1000 liye" and it is filed. English and Roman Urdu, offline-first, groups with split balances,
optional Firebase sync and Google Sheet backup.

- Privacy policy: https://abdullah-ajmal147.github.io/spendline/
- Notes for contributors: `CLAUDE.md`. Play Store launch notes: `PLAY_STORE.md`.

## Run

```
flutter pub get
flutter test
flutter run
```

Release signing uses `android/key.properties` (not in the repo). Without it the release build falls back to the debug key.
