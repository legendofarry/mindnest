# Web Local CanvasKit Startup Fix

## Version
- `1.0.2`

## Scope
- Flutter web bootstrap
- Local Chrome development startup

## Why This Pass Happened
- Chrome debug runs were failing before the app could start because Flutter was trying to dynamically import CanvasKit from `www.gstatic.com`.
- That makes local development brittle whenever the remote engine bundle is blocked, slow, or unavailable.

## What Changed

### 1) Web bootstrap now prefers local CanvasKit on localhost
- Added a custom `web/flutter_bootstrap.js`.
- Kept the standard Flutter loader and build config injection in place.
- Switched the CanvasKit base URL to the local `canvaskit/` asset path when the app is running on localhost, `127.0.0.1`, or `::1`.

### 2) Release behavior stays sensible
- The bootstrap still passes the normal service worker version when Flutter provides one.
- Non-local hosts continue to use the default CanvasKit path selection, so the fix stays focused on development startup rather than forcing an unnecessary deployment-wide renderer change.

## External Platform Check
- Reviewed the current Flutter web loader behavior in the installed SDK before editing.
- Confirmed that `web/flutter_bootstrap.js` is a supported override point in Flutter 3.41.
- Confirmed the dev web asset server can serve local `canvaskit/` assets from the SDK, so this is a platform-level fix rather than a guess.

## Before
- `flutter run -d chrome` could reach the app shell, then fail while importing CanvasKit from `gstatic`.
- The failure happened before the first real Flutter frame, so the app never got a chance to show its own UI.

## After
- Local Chrome runs use the SDK-hosted CanvasKit bundle instead of the remote CDN.
- Startup should no longer depend on that remote import just to get the app on screen.
- The branded loader still remains in place while Flutter initializes.

## Validation Intent
- Re-run the Chrome web startup path and confirm the dynamic import no longer points at `www.gstatic.com`.
- If needed, follow up with a focused Flutter web analyze/build pass once startup is confirmed.
