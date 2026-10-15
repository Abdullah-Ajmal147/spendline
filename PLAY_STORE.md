# Play Store launch pack

Bundle: build/app/outputs/bundle/release/app-release.aab  (package com.spendline.spendline, 1.0.0+1)
Upload key: ~/spendline-signing/spendline-upload.jks  (passwords in android/key.properties). BACK THESE UP.
Upload-key SHA-1: 78:0E:26:7F:33:D7:32:12:3A:9A:C2:03:19:B2:00:8B:2D:98:AB:68

## Steps only the account owner can do
1. play.google.com/console: create a developer account (one-time US$25 fee, ID verification).
2. Create app > Spendline > free > App. Enable Play App Signing and upload the .aab (Internal testing first).
3. Firebase > Project settings > Android app: add BOTH SHA-1s: the upload key above and the
   "App signing key certificate" SHA-1 from Play Console > Setup > App signing. Without the second,
   Google sign-in fails for store installs.
4. Complete: Store listing, Content rating, Data safety (below), Target audience (not for children),
   Privacy policy URL (host the text below, e.g. on GitHub Pages).
5. New personal accounts must run a closed test with 12+ testers for 14 days before production.

## Listing
Title: Spendline: Expense Tracker
Short (80): Type "lunch 500" or "ali ko 1000 diye". Roman Urdu and English. Split with friends.
Full: Spendline turns a chat message into an expense. Write it the way you talk, or speak it.
- Understands English and Roman Urdu (kal, diye, liye, hazaar)
- See who owes you and send a WhatsApp reminder
- Split trips with friends, see who pays whom
- Works offline; optional backup and sync with your own Google account and a Google Sheet copy
Category: Finance. Tags: expense tracker, udhaar, split bills.

## Data safety answers
- Collected & shared: none shared with third parties.
- Collected (optional, only if Backup & sync is on): email address (Google sign-in), financial info
  you enter (entries). Encrypted in transit. User can delete by turning sync off and deleting the data.
- Microphone: used only while you tap the mic, processed by the phone's speech service.

## Privacy policy (host this text)
Spendline stores your entries on your phone. If you turn on Backup & sync, your entries, groups and
Google email are stored in a private Firebase database that only your account can read, and a
"Spendline" spreadsheet is created in your own Google Drive. We do not sell data, show ads, or share
it with third parties. Microphone audio is used only while you tap the mic and is handled by your
phone's speech service. To delete your data, turn off Backup & sync and email the developer to remove
the cloud copy. Contact: abdullahajmal148@gmail.com
