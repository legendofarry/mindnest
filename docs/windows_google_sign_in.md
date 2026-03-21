# Windows Google Sign-In

MindNest now uses a real desktop Google OAuth flow on Windows:

- opens the user's default browser
- uses Google OAuth 2.0 for installed apps with PKCE
- listens on a loopback redirect URL
- exchanges the authorization code for tokens
- signs in to Firebase Auth with the returned Google credential

## Required setup

Create a Google OAuth client for a desktop app in Google Cloud Console, then run the Windows app with:

```powershell
flutter run -d windows --dart-define=GOOGLE_WINDOWS_CLIENT_ID=your_desktop_client_id.apps.googleusercontent.com
```

If your OAuth client also requires a secret, add:

```powershell
flutter run -d windows `
  --dart-define=GOOGLE_WINDOWS_CLIENT_ID=your_desktop_client_id.apps.googleusercontent.com `
  --dart-define=GOOGLE_WINDOWS_CLIENT_SECRET=your_client_secret
```

## Notes

- Keep `GOOGLE_WINDOWS_CLIENT_ID` out of source control when possible.
- Prefer a Desktop app OAuth client for the Windows app.
- The flow uses a loopback redirect like `http://127.0.0.1:{port}/oauth2redirect`.
- Google sign-in still requires the Google provider to be enabled in Firebase Authentication.
