# Teraji Rebrand Notes

Version: 1.0.1

## What Changed

- Public app branding now uses `Teraji` on web metadata, browser titles, AI assistant copy, setup flows, notification copy, and export labels.
- Primary web URL references now point to `https://teraji.netlify.app/`.
- Browser and Windows handoff pages now show Teraji wording.
- Notification fallback titles and push-dispatch branding now use Teraji.
- Exported files now use Teraji-prefixed names and folders.

## What Stayed The Same

- Flutter package name remains `mindnest`.
- Firebase project identifiers remain unchanged.
- Internal class names such as `MindNestApp`, `MindNestTheme`, `MindNestShell`, and `MindNestLogo` remain unchanged for safety.
- Existing asset file names remain unchanged.

## Validation

- `dart format` completed successfully on the touched Dart files.
- `flutter analyze lib` completed with no issues.

## Notes

- The old Netlify origin is still accepted in backend origin checks for backward compatibility.
- This is a safe brand migration, not a full technical rename of the repository or Firebase setup.
