# Firebase Setup

This project uses FlutterFire with generated options in `lib/firebase_options.dart`.

## 1. Prerequisites

1. Install Firebase CLI: `npm install -g firebase-tools`
2. Install FlutterFire CLI: `dart pub global activate flutterfire_cli`
3. Authenticate:
   - `firebase login`

## 2. Configure Platforms

Run from project root:

```bash
flutterfire configure --project=mindnest-923fb --platforms=android,ios,web,macos,windows
```

This regenerates:

1. `lib/firebase_options.dart`
2. `android/app/google-services.json`
3. `ios/Runner/GoogleService-Info.plist`
4. `macos/Runner/GoogleService-Info.plist`

## 3. iOS Bundle Id

Current iOS bundle id in `lib/firebase_options.dart` is `com.example.mindnest`.
If you change bundle id in Xcode, rerun `flutterfire configure` to keep Firebase config aligned.

## 4. Run with Firebase Emulators (Optional)

Start emulators:

```bash
firebase emulators:start --only auth,firestore
```

Run app against emulators:

```bash
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

## 5. Security Rules Deploy

Local test:

```bash
firebase emulators:start --only firestore
```

Deploy:

```bash
firebase deploy --only firestore:rules
```
