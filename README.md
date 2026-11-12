# Spendline

Type how you spent money in plain words. Spendline turns it into a clean row in your own Google Sheet.

| You type | Type | Person | Category | Amount |
|---|---|---|---|---|
| Give to rizwan 1000 | Given | Rizwan | Lending | 1000 |
| pay for lunch 500 | Expense | | Food | 500 |
| Uber 350 yesterday | Expense, dated yesterday | | Transport | 350 |
| received 2k from Ali | Received | Ali | Lending | 2000 |
| rizwan ko 1000 diye | Given | Rizwan | Lending | 1000 |

Before saving, a preview card shows what was understood, and every field can be edited.
The home screen shows this month's spending, the last 14 days, and how much each person owes you.
If you're offline, entries are kept on the phone and sync when you're back online.

## 1. Set up the Google side (once, about 5 minutes)

1. Open https://script.google.com and make a new project.
2. Paste `apps_script/Code.gs` into it.
3. On the line `const APP_KEY = 'CHANGE-ME';`, replace `CHANGE-ME` with a long phrase only you know.
4. Click **Deploy → New deployment → Web app**. Set **Execute as** to *Me* and **Who has access** to *Anyone*. Then authorize.
5. Copy the Web app URL. It ends in `/exec`.

Your sheet can stay private. The script runs as you, and it only answers requests that carry your APP_KEY.

## 2. Build the app

You need Flutter 3.35 or newer.

```bash
bash scripts/setup_platforms.sh   # creates android/ and ios/ with the right settings
flutter test                      # parser tests
flutter run                       # with your phone plugged in
```

When the app opens:
1. Paste the `/exec` URL and your APP_KEY.
2. Paste the link to your Google Sheet. The app adds an **Expenses** tab to it.

## Smart parsing (optional)

Turn this on in Settings. It downloads Qwen3 0.6B, an open-source model of about 350 MB, and runs it on the phone. It is only used when the built-in parser isn't sure about a sentence, and nothing is sent to any AI service.

It needs Android 11+ on an arm64 phone, or iOS 15+.

## Working on it with Claude Code

Open this folder in a terminal and run `claude`. `CLAUDE.md` describes the structure, the commands, and the first steps to verify the build.
