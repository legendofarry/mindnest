# Windows Store Resubmission

## Fixed in source

- The MSIX package now uses `assets/logo.png` for Store tile/logo generation.
- The native Windows runner icon at `windows/runner/resources/app_icon.ico` is regenerated from the MindNest logo.
- A fresh package has been built at `build/windows/x64/runner/Release/mindnest.msix`.

## Remaining Microsoft certification requirements

These two items must be completed in Partner Center before resubmitting.

### 1. Provide working test accounts

Microsoft could not test the app because login is required.

MindNest uses role-based accounts, so the reviewer package must contain four
real accounts under the same approved institution:

1. Institution Admin
2. Counselor
3. Student
4. Staff

An automated seeding helper now exists for this:

1. Copy `backend/push-dispatch/reviewer-accounts.config.example.json` to
   `backend/push-dispatch/reviewer-accounts.config.local.json`.
2. Fill in the real review emails, passwords, phone numbers, and institution
   details.
3. Run:

   ```bash
   cd backend/push-dispatch
   npm install
   npm run create:reviewer-accounts -- --config reviewer-accounts.config.local.json --service-account C:\path\to\service-account.json
   ```

   If you prefer environment variables, the script also accepts:
   - `FIREBASE_SERVICE_ACCOUNT_PATH`
   - `GOOGLE_APPLICATION_CREDENTIALS`
   - `FIREBASE_SERVICE_ACCOUNT_JSON`

4. Paste the generated notes from
   `docs/windows_store_review_notes.local.txt` into the Partner Center testing
   notes field.

What the script prepares:

- Firebase Auth users for all four reviewer roles
- An approved institution shared by those accounts
- Active role memberships for admin, counselor, student, and staff
- Accepted invite history for counselor, student, and staff
- Completed onboarding state for student and staff
- Completed counselor setup data for the counselor account

### 2. Replace login-only screenshots

Microsoft rejected the listing because the uploaded images only showed the splash and/or login experience.

Upload screenshots that show the actual in-app product experience after login.

Recommended desktop screenshot set:

1. Main dashboard/home screen
2. Counselor directory or counselor profile
3. Appointments or session details
4. Live hub, notifications, or care plan

Recommended rules:

- Use real app screens, not placeholder art.
- Show the actual signed-in product experience.
- Avoid using only auth screens.
- Capture clean desktop screenshots with readable UI.

## Resubmission flow

1. Upload the rebuilt `mindnest.msix` package if needed.
2. Replace the Store screenshots with real in-app screenshots.
3. Add the generated reviewer notes in the testing notes.
4. Resubmit for certification.
