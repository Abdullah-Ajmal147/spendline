/// Cloud setup baked into the app, so users never see a setup screen.
///
/// These come from the free Firebase project "Spendline" (spendline-8ea2c, Spark plan, Firestore in
/// asia-south1). None of them are secrets: the Web API key is public by design and access is
/// protected by the Firestore security rules (each user can only touch users/{their uid}).
/// To use another project, change them here or paste new values in Settings > Set up.
const String kGoogleServerClientId = '909930681578-hk125c20e705gc135c54frof1snkeki0.apps.googleusercontent.com';
const String kFirebaseProjectId = 'spendline-8ea2c';
const String kFirebaseApiKey = 'AIzaSyCzfVMfzylcsNWczo1Ko0js50O_vYeBx1M';
