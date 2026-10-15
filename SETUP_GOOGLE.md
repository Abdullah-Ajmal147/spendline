# Google Sheets + Firebase sync: one-time setup

> **Status:** done. Firebase project `spendline-8ea2c` (Spark plan, Firestore asia-south1) exists, Google
> sign-in is enabled, the Android app + debug SHA-1 are registered, rules are published, and the Sheets
> and Drive APIs are enabled. The values are baked into `lib/config.dart`. Before a Play Store release,
> add the Play **App signing key** SHA-1 under Project settings > Your apps.


Everything here is free (Firebase Spark plan, no card). The app also has this guide
built in: Settings -> "Set up", with copy buttons and a test button per connection.

Values for this machine's **debug** build:

- Package name: `com.spendline.spendline`
- Debug SHA-1: `75:87:26:CF:DF:6E:D1:47:6A:B7:6D:D8:E0:E6:D2:03:89:90:F5:7E`
  (regenerate: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`)
- For the Play Store build add the **App signing key** SHA-1 from Play Console > Setup > App signing.
  A release APK built locally with the debug key uses the debug SHA-1 above.

Steps

1. https://console.firebase.google.com -> Add project (Analytics off).
2. Build > Authentication > Sign-in method > Google > Enable. Open it again and copy
   **Web client ID** (Web SDK configuration).
3. Project settings > General > Add app > Android: package + SHA-1 above. Skip google-services.json.
4. Project settings > General: copy **Project ID** and **Web API Key**.
5. Build > Firestore Database > Create (production mode) > Rules > paste and publish:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{uid}/{document=**} {
         allow read, write: if request.auth != null && request.auth.uid == uid;
       }
     }
   }
   ```
6. Google Cloud console (same project) > APIs & Services > Library: enable **Google Sheets API**
   and **Google Drive API**. OAuth consent screen: add scope `drive.file`, add your Google
   account under Test users while in Testing.
7. In the app: Settings -> Set up -> paste the three values -> "Test Google Sheet" / "Test Firebase".

To bake the values into a release build instead of pasting, set `kGoogleServerClientId` in
`lib/config.dart` (Project ID and API key are entered in the app).
