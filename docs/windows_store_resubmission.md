# Windows Store Resubmission

## Fixed in source

- The MSIX package now uses `assets/logo.png` for Store tile/logo generation.
- The native Windows runner icon at `windows/runner/resources/app_icon.ico` is regenerated from the MindNest logo.
- A fresh package has been built at `build/windows/x64/runner/Release/mindnest.msix`.

## Remaining Microsoft certification requirements

These two items must be completed in Partner Center before resubmitting.

### 1. Provide working test accounts

Microsoft could not test the app because login is required.

Add reviewer instructions in the submission's testing notes using real credentials.

Suggested note format:

```text
Certification accounts for review:

Institution Admin
Email: <admin-review-email>
Password: <admin-review-password>

Counselor
Email: <counselor-review-email>
Password: <counselor-review-password>

Student
Email: <student-review-email>
Password: <student-review-password>

Staff
Email: <staff-review-email>
Password: <staff-review-password>

Steps:
1. Launch MindNest.
2. Sign in with the Institution Admin account first.
3. Review the institution admin workspace and invite/member flows.
4. Sign out and then sign in with the Counselor, Student, and Staff accounts to review each role-specific workspace.
5. Use the dashboard, appointments, counselor directory, notifications, and other visible product areas for review.

Notes:
- This account is intended for Microsoft Store certification only.
- MindNest uses role-based accounts, so one account cannot accurately represent all roles.
- All review accounts belong to the same institution so the full institution flow can be tested end to end.
```

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
3. Add the certification test account in the testing notes.
4. Resubmit for certification.
