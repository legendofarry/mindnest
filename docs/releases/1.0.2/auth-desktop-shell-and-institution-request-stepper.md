# Auth Desktop Shell Lifecycle Fix and Institution Request Stepper

## Version
- `1.0.2`

## Scope
- Shared desktop auth shell lifecycle
- Institution request screen layout

## Why This Pass Happened
- The shared desktop auth shell was creating animation controllers lazily, which could trigger an ancestor lookup after the widget had already been deactivated during dispose.
- The institution request screen was also too tall on desktop, forcing the form to scroll instead of fitting the viewport cleanly.

## What Changed

### 1) Shared auth shell now initializes its hover controllers early
- Moved the four desktop tilt/shift `AnimationController`s into `initState`.
- This avoids the lazy initialisation path during `dispose()`, which is where the deactivated-ancestor assertion was being raised.

### 2) Institution request now uses a compact two-step flow
- Reworked `register_institution_school_request_screen.dart` into a two-step desktop-friendly flow.
- Step 1 keeps only the approved catalog search and results list visible.
- Step 2 shows the confirmation checkbox, institution name field, and submit action.
- This removes the long vertical stack that was pushing the page below the fold.

### 3) The form stays readable without feeling cramped
- Added a small desktop step rail so the user can see progress at a glance.
- Kept the mobile layout functional while making the desktop experience fit the screen more naturally.
- Preserved the existing validation and Firestore submission flow.

## External Platform Check
- Reviewed the Flutter widget lifecycle behavior around `TickerProviderStateMixin` before changing the shared shell.
- Confirmed the fix is local to the app code and does not depend on any Firebase, auth, or browser platform change.

## Before
- Disposing the auth shell could try to create animation controllers after the widget tree was no longer stable.
- The institution request screen required too much vertical scrolling on desktop.

## After
- The shared auth shell can dispose cleanly without triggering the ancestor lookup assertion.
- The request flow is shorter, clearer, and fits the desktop viewport much better.
- Users now move through the request in steps instead of a tall single column.

## Validation
- Ran `dart format` on the touched Dart files.
- Ran a focused `flutter analyze` on the shared auth shell and institution request screen.
- Rebuilt the web app with `flutter build web --debug` successfully.
