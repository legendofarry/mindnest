# Login Biometric Entry Shell

Date: 2026-05-31
App version: 1.0.2+3

## Summary

The desktop login screen now opens on a biometric-first entry stage inspired by the shared reference: dark MindNest atmosphere, centered fingerprint orb, Google pill, "Use email instead" fallback, animated orbit dot, and a scanning skeleton state.

## Before

- Desktop login showed the email/password form immediately.
- The fingerprint area was only a static decorative companion beside the form.
- Google sign-in lived inside the form card, so the first screen did not feel like a biometric/passkey-style entry.

## After

- Desktop login starts with the biometric stage only.
- Email/password form is hidden until the user clicks `Use email instead`.
- Google sign-in remains available from the floating Google pill.
- The biometric button runs a safe skeleton animation for now:
  - fingerprint orb expands into a scanning capsule;
  - text changes to `Scanning...`;
  - the white orbit dot continues revolving around the ring;
  - after the skeleton completes, users are told to use Google or email for now.
- Hovering the Google and email fallback pills brightens their background, matching the reference interaction style.
- The desktop create-account link moved to the top-right corner.

## Platform Notes

- Web/Desktop: new biometric-first visual shell is active at desktop width.
- Android/iOS/Mobile-width web: existing mobile form flow remains unchanged for now.
- Windows desktop: existing top-right window controls are still preserved beside the create-account link.

## Validation

- Ran `dart format lib\features\auth\presentation\login_screen.dart`.
- Ran `flutter analyze lib\features\auth\presentation\login_screen.dart`.
- Ran `flutter build web --debug`.

## Known Limitations

- Biometrics are visual-only in this update. No WebAuthn, passkey, Face ID, Touch ID, Windows Hello, Android BiometricPrompt, or iOS LocalAuthentication flow has been wired yet.
- The debug web build still reports existing `dart_webrtc` WebAssembly dry-run warnings from the dependency cache. The build succeeds.

## Future Upgrade Ideas

- Add passkey/WebAuthn sign-in on web so the fingerprint shell becomes real authentication rather than a skeleton.
- Add Windows Hello support for the Windows desktop build.
- Add Android/iOS biometric unlock after a successful first sign-in, guarded by secure local storage.
