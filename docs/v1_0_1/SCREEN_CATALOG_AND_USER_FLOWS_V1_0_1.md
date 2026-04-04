# MindNest Screen Catalog And User Flows

Version: `1.0.1`  
Last updated: `2026-04-03`

This is the tester's screen map for MindNest. It is meant to answer four things quickly:

1. which screens exist
2. which platform can show them
3. which role can see them
4. how a user actually gets there

Use this file together with:

- `APP_REFERENCE_V1_0_1.md` for system behaviour and hidden state
- `TEST_TODO_V1_0_1.md` for test cases
- `ROLE_TEST_MATRIX_V1_0_1.md` for role permissions

## 1. Platform Key

- `Web`: browser experience
- `Windows`: Windows desktop app
- `Android`: Android app
- `iOS`: iPhone/iPad app

## 2. Reading Rules

MindNest does not have one universal screen order. Big companies handle apps like this the same way:

- auth state changes the first screen
- email verification can interrupt the flow
- onboarding can interrupt the flow
- invite flows can interrupt the flow
- role changes can change the workspace
- Windows has some route restrictions that web/mobile do not

So the correct testing order is:

1. choose platform
2. choose role
3. choose entry condition
4. follow the expected screen order below

## 3. Platform-First User Viewing Order

This section is the quickest "what does the user likely see, in order?" map.

### Web

#### Guest

Typical order:

1. `Login` (`/`)
2. `Register` or `Forgot Password`
3. `Register Details` or `Register Institution`
4. `Verify Email`
5. `Onboarding Questionnaire` if role requires it
6. `Onboarding Loading`
7. role destination

Invite variant:

1. `Login` or `Register`
2. `Verify Email`
3. `Invite Accept`
4. `Onboarding Questionnaire` only if actually incomplete
5. destination for connected role

#### Individual / Student / Staff

Typical order:

1. `Login`
2. `Verify Email` if unverified
3. `Onboarding Questionnaire` if incomplete
4. `Onboarding Loading`
5. `Home`
6. deeper screens from navigation, header, cards, or notifications

Likely next screens:

- `Counselor Directory`
- `Counselor Profile`
- `Student Appointments`
- `Notifications`
- `Notification Details`
- `Privacy Controls`
- `Live Hub`
- `Live Room`
- `Session Details`
- `Student Care Plan`
- `Crisis Counselor Support`

#### Counselor

Typical order:

1. `Login`
2. `Verify Email` if unverified
3. `Counselor Invite Waiting` if counselor access is still pending
4. `Invite Accept` when counselor invite is opened
5. `Counselor Setup` if setup is incomplete
6. `Counselor Dashboard`
7. same-shell workspace navigation:
   - `Counselor Appointments`
   - `Counselor Live Hub`
   - `Counselor Availability`
   - `Counselor Notifications`
   - `Counselor Settings`

#### Institution Admin

Typical order:

1. `Login`
2. `Verify Email`
3. `Register Institution Success` or `Institution Pending`
4. `Institution Admin`
5. `Institution Admin Profile` or `Admin Messages`

#### Owner

Typical order:

1. `Login`
2. `Owner Dashboard`

### Windows

Important Windows reality:

- Windows does not currently support the normal live workflow
- Windows can redirect to `Windows Web Setup Required`
- guest registration is not the normal primary Windows flow

#### Guest

Typical order:

1. `Login`
2. `Forgot Password` if needed
3. `Verify Email` if account exists but is unverified

#### Individual / Student / Staff

Typical order:

1. `Login`
2. `Verify Email` if unverified
3. `Onboarding Questionnaire` if incomplete
4. `Onboarding Loading`
5. `Home`

Likely next screens:

- `Counselor Directory`
- `Counselor Profile`
- `Student Appointments`
- `Notifications`
- `Notification Details`
- `Privacy Controls`
- `Session Details`
- `Student Care Plan`
- `Crisis Counselor Support`

User should not normally see:

- `Live Hub`
- `Live Room`

Instead, blocked live access can lead to:

- `Windows Web Setup Required`

#### Counselor

Typical order:

1. `Login`
2. `Verify Email`
3. `Counselor Invite Waiting` if pending
4. `Invite Accept`
5. `Counselor Setup` if incomplete
6. `Counselor Dashboard`
7. same-shell workspace navigation:
   - `Counselor Appointments`
   - `Counselor Availability`
   - `Counselor Notifications`
   - `Counselor Settings`

Windows counselor should not normally see:

- active `Counselor Live Hub`
- active `Live Room`

#### Institution Admin

Typical order:

1. `Login`
2. `Verify Email`
3. `Institution Pending` or `Institution Admin`
4. `Institution Admin Profile` / `Admin Messages`

#### Owner

Typical order:

1. `Login`
2. `Owner Dashboard`

### Android

Android is the closest to the full mobile app flow.

#### Guest

Typical order:

1. `Login`
2. `Register` or `Forgot Password`
3. `Register Details` or `Register Institution`
4. `Verify Email`
5. `Onboarding Questionnaire`
6. `Onboarding Loading`
7. role destination

#### Individual / Student / Staff

Typical order:

1. `Login`
2. `Verify Email`
3. `Onboarding Questionnaire` if incomplete
4. `Onboarding Loading`
5. `Home`

Likely next screens:

- `Counselor Directory`
- `Counselor Profile`
- `Student Appointments`
- `Notifications`
- `Notification Details`
- `Privacy Controls`
- `Live Hub`
- `Live Room`
- `Session Details`
- `Student Care Plan`
- `Crisis Counselor Support`

#### Counselor

Typical order:

1. `Login`
2. `Verify Email`
3. `Counselor Invite Waiting` if pending
4. `Invite Accept`
5. `Counselor Setup`
6. `Counselor Dashboard`
7. same-shell workspace navigation:
   - `Counselor Appointments`
   - `Counselor Live Hub`
   - `Counselor Availability`
   - `Counselor Notifications`
   - `Counselor Settings`

#### Institution Admin

Typical order:

1. `Login`
2. `Verify Email`
3. `Institution Pending` or `Institution Admin`
4. `Institution Admin Profile` / `Admin Messages`

#### Owner

Typical order:

1. `Login`
2. `Owner Dashboard`

### iOS

iOS should follow the same broad mobile order as Android.

#### Guest

1. `Login`
2. `Register` or `Forgot Password`
3. `Register Details` or `Register Institution`
4. `Verify Email`
5. `Onboarding Questionnaire`
6. `Onboarding Loading`
7. role destination

#### Individual / Student / Staff

1. `Login`
2. `Verify Email`
3. `Onboarding Questionnaire` if incomplete
4. `Onboarding Loading`
5. `Home`
6. deeper care, notification, live, and profile screens

#### Counselor

1. `Login`
2. `Verify Email`
3. `Counselor Invite Waiting` if pending
4. `Invite Accept`
5. `Counselor Setup`
6. `Counselor Dashboard`
7. same-shell workspace navigation:
   - `Counselor Appointments`
   - `Counselor Live Hub`
   - `Counselor Availability`
   - `Counselor Notifications`
   - `Counselor Settings`

#### Institution Admin / Owner

Expected order mirrors Android:

1. `Login`
2. verification / pending check
3. destination workspace

## 4. Role-First Notes

This section is useful when testing one role deeply instead of testing one platform deeply.

### Guest

Main screens:

- `Login`
- `Forgot Password`
- `Register`
- `Register Details`
- `Register Institution`
- `Register Institution School Request`
- `Register Institution Success`
- `Verify Email`

How guest users reach protected screens:

- by trying to access a deep link while unauthenticated
- by opening an invite link
- by following auth CTAs

### Individual

Main order:

1. `Login`
2. `Verify Email`
3. `Onboarding Questionnaire`
4. `Onboarding Loading`
5. `Home`

Common next screens:

- `Counselor Directory`
- `Counselor Profile`
- `Notifications`
- `Notification Details`
- `Privacy Controls`
- `Live Hub` on supported platforms
- `Live Room` on supported platforms

Important role-change test:

1. user starts as `individual`
2. user later receives student or staff invite
3. user opens `Invite Accept`
4. connection succeeds
5. user should move into linked-role experience without being wrongly sent back to step 1 onboarding

### Student

Main order:

1. `Login`
2. `Verify Email`
3. `Onboarding Questionnaire` if incomplete
4. `Onboarding Loading`
5. `Home`

Common next screens:

- `Student Appointments`
- `Session Details`
- `Student Care Plan`
- `Notifications`
- `Notification Details`
- `Live Hub`
- `Live Room`
- `Counselor Directory`
- `Counselor Profile`

### Staff

Main order:

1. `Login`
2. `Verify Email`
3. `Onboarding Questionnaire` if incomplete
4. `Onboarding Loading`
5. `Home`

Common next screens:

- `Notifications`
- `Notification Details`
- `Live Hub`
- `Live Room`
- `Counselor Directory`
- `Counselor Profile`
- `Privacy Controls`

### Counselor

Main order:

1. `Login`
2. `Verify Email`
3. `Counselor Invite Waiting` if invite or access is still pending
4. `Invite Accept`
5. `Counselor Setup` if incomplete
6. `Counselor Dashboard`

Same-shell counselor workspace screens:

- `Counselor Dashboard`
- `Counselor Appointments`
- `Counselor Availability`
- `Counselor Live Hub` where supported
- `Counselor Notifications`
- `Counselor Settings`

Adjacent counselor screens:

- `Counselor Directory`
- `Counselor Profile`
- `Session Details`
- `Live Room`

### Institution Admin

Main order:

1. `Login`
2. `Verify Email`
3. `Institution Pending` or `Institution Admin`

Related screens:

- `Institution Admin`
- `Institution Admin Profile`
- `Admin Messages`
- `Institution Pending`

### Owner

Main order:

1. `Login`
2. `Owner Dashboard`

## 5. Full Route Screen Inventory

This is the route-level catalog from the current router.

| Screen | Route / surface | Platforms | Roles | Typical previous screen | How user gets there |
| --- | --- | --- | --- | --- | --- |
| Login | `/` | Web, Windows, Android, iOS | Guest | app launch, sign-out, auth redirect | root route |
| Forgot Password | `/forgot-password` | Web, Windows, Android, iOS | Guest | `Login` | tap forgot-password CTA |
| Register | `/register` | Web, Android, iOS | Guest | `Login` | tap register CTA |
| Register Details | `/register-details` | Web, Android, iOS | Guest | `Register` | choose personal registration path |
| Register Institution | `/register-institution` | Web, Android, iOS | Guest / future admin | `Register` | choose institution registration path |
| Register Institution School Request | `/register-institution-school-request` | Web, Android, iOS | Guest / future admin | `Register Institution` | continue institution registration |
| Register Institution Success | `/register-institution-success` | Web, Android, iOS | Institution admin applicant | `Register Institution School Request` | finish institution registration |
| Verify Email | `/verify-email` | Web, Windows, Android, iOS | New user | signup flow, login guard | user is signed in but not verified |
| Windows Web Setup Required | `/windows-web-setup-required` | Windows only | Any affected role | blocked Windows action | Windows-specific redirect |
| Counselor Invite Waiting | `/counselor-invite-waiting` | Web, Windows, Android, iOS | Counselor-intent | `Verify Email` or counselor route guard | counselor has no usable institution access yet |
| Invite Accept | `/invite-accept` | Web, Windows, Android, iOS | Invited user | notification, email link, direct deep link | invite link or invite route with query params |
| Onboarding Questionnaire | `/onboarding` | Web, Windows, Android, iOS | Individual, student, staff | `Verify Email` or route guard | onboarding incomplete |
| Onboarding Loading | `/onboarding-loading` | Web, Windows, Android, iOS | Individual, student, staff | `Onboarding Questionnaire` | questionnaire submit |
| Counselor Setup | `/counselor-setup` | Web, Windows, Android, iOS | Counselor | `Invite Accept`, `Counselor Invite Waiting`, route guard | counselor setup incomplete |
| Counselor Dashboard | `/counselor-dashboard` | Web, Windows, Android, iOS | Counselor | `Counselor Setup`, login redirect, shell nav | counselor default workspace |
| Counselor Appointments | `/counselor-appointments` | Web, Windows, Android, iOS | Counselor | `Counselor Dashboard` or shell nav | tap `Sessions` in counselor shell |
| Counselor Availability | `/counselor-availability` | Web, Windows, Android, iOS | Counselor | `Counselor Dashboard` or shell nav | tap `Availability` in counselor shell |
| Counselor Live Hub | `/counselor-live-hub` | Web, Android, iOS | Counselor | `Counselor Dashboard` or shell nav | tap `Live` in counselor shell |
| Counselor Notifications | `/counselor-notifications` | Web, Windows, Android, iOS | Counselor | any counselor shell screen | tap top bell in counselor shell |
| Counselor Settings | `/counselor-settings` | Web, Windows, Android, iOS | Counselor | any counselor shell screen | tap top profile icon in counselor shell |
| Home | `/home` | Web, Windows, Android, iOS | Individual, student, staff | onboarding finish, login redirect | signed-in general user default route |
| Counselor Directory | `/counselors` | Web, Windows, Android, iOS | Individual, student, staff, counselor | `Home`, desktop shell nav, counselor shell nav | open counselor discovery screen |
| Student Appointments | `/student-appointments` | Web, Windows, Android, iOS | Student | `Home`, desktop shell nav, notification deep link | open student appointment workflow |
| Live Hub | `/live-hub` | Web, Android, iOS | Student, staff, counselor | `Home`, desktop nav, live CTA | open live session hub |
| Counselor Profile | `/counselor-profile` | Web, Windows, Android, iOS | General users, counselor | `Counselor Directory`, recommendation CTA | open a specific counselor profile |
| Session Details | `/session-details` | Web, Windows, Android, iOS | Student, counselor | appointments list, notification action | open one appointment/session |
| Notifications | `/notifications` | Web, Windows, Android, iOS | General users | `Home`, header bell, deep link | open notification center outside counselor shell |
| Notification Details | `/notification-details` | Web, Windows, Android, iOS | General users | `Notifications` or deep link | open one notification directly |
| Student Care Plan | `/care-plan` | Web, Windows, Android, iOS | Student | `Home`, care route, notification | open care-plan view |
| Crisis Counselor Support | `/crisis-counselor-support` | Web, Windows, Android, iOS | General users / student | support CTA | open crisis support view |
| Live Room | `/live-room` | Web, Android, iOS | Eligible live participants | `Live Hub`, session invitation, notification | join a live audio room |
| Privacy Controls | `/privacy-controls` | Web, Windows, Android, iOS | Signed-in users | profile/header action | open privacy settings |
| Join Institution | `/join-institution` | Web, Windows, Android, iOS | Signed-in general users | join-code CTA | currently redirects to `/home?openJoinCode=1` |
| Institution Admin | `/institution-admin` | Web, Windows, Android, iOS | Institution admin | login redirect, pending approval clear | open admin workspace |
| Institution Admin Profile | `/institution-admin/profile` | Web, Windows, Android, iOS | Institution admin | `Institution Admin` | tap admin profile/settings path |
| Admin Messages | `/institution-admin/messages` | Web, Windows, Android, iOS | Institution admin | `Institution Admin` | tap admin messages path |
| Institution Pending | `/institution-pending` | Web, Windows, Android, iOS | Institution admin applicant | login redirect or admin guard | institution is not yet approved |
| Owner Dashboard | `/owner-dashboard` | Web, Windows, Android, iOS | Owner | login redirect | account matches owner config |

## 6. Non-Route Screens, Panels, And Embedded Surfaces

These are not always standalone routes, but users still experience them as real app surfaces.

| Surface | File | Platforms | Roles | How user gets there |
| --- | --- | --- | --- | --- |
| Account Export Sheet | `lib/features/auth/presentation/account_export_sheet.dart` | Web, Windows, Android, iOS | Signed-in users where exposed | trigger account export action |
| Terms And Privacy Screen | `lib/features/auth/presentation/terms_and_privacy_screen.dart` | Web, Windows, Android, iOS | Guest / signed-in users | legal links from auth or settings paths |
| Home AI Assistant Section | `lib/features/ai/presentation/home_ai_assistant_section.dart` | Web, Windows, Android, iOS | General users | appears inside `Home` |
| Assistant Chat Sheet | `lib/features/ai/presentation/home_ai_assistant_section.dart` | Web, Windows, Android, iOS | General users | open assistant from AI section |
| Assistant FAB | `lib/features/ai/presentation/assistant_fab.dart` | Web, Windows, Android, iOS | General users | tap floating AI action where enabled |
| Wellness Check-In Card | `lib/features/home/presentation/widgets/wellness_check_in_card.dart` | Web, Windows, Android, iOS | General users | appears inside `Home` |
| Join Code Inline Panel | `lib/features/home/presentation/home_screen.dart` | Web, Windows, Android, iOS | Signed-in general users | `Join Institution` redirect or join-code CTA |
| Desktop Primary Shell | `lib/core/ui/desktop_primary_shell.dart` | Web desktop, Windows | Individual, student, staff | wraps `/home`, `/counselors`, `/student-appointments`, `/live-hub` |
| Desktop Section Nav | `lib/core/ui/desktop_section_shell.dart` | Web desktop, Windows | Individual, student, staff | sidebar inside desktop shell |
| Counselor Workspace Shell | `lib/features/counselor/presentation/counselor_workspace_shell.dart` | Web, Windows, Android, iOS | Counselor | wraps counselor workspace routes |
| Counselor Notifications Panel State | `lib/features/counselor/presentation/counselor_workspace_shell.dart` | Web, Windows, Android, iOS | Counselor | bell toggle inside counselor shell |
| Counselor Settings Panel State | `lib/features/counselor/presentation/counselor_workspace_shell.dart` | Web, Windows, Android, iOS | Counselor | profile toggle inside counselor shell |

## 7. Platform-Specific Testing Notes

### Web

- web is the fullest route surface
- deep links are easiest to test here
- onboarding, invite, notification, and live flows are easiest to reproduce here

### Windows

- live is intentionally removed as a normal workflow
- some blocked flows go to `Windows Web Setup Required`
- Windows shell and route testing should focus on stability, quota-sensitive flows, and correct blocked-path messaging

### Android

- mobile width can surface hidden layout bugs faster than web desktop
- counselor shell transitions, appointments, and availability are especially worth retesting here

### iOS

- should largely mirror Android behaviour
- still worth separate validation for auth, onboarding, notifications, and live entry paths

## 8. Best Screens For Fast Regression Testing

If HIM wants quick confidence, hit these first:

1. `Login`
2. `Verify Email`
3. `Onboarding Questionnaire`
4. `Invite Accept`
5. `Home`
6. `Notifications`
7. `Counselor Dashboard`
8. `Counselor Appointments`
9. `Counselor Availability`
10. `Counselor Live Hub`
11. `Live Room`
12. `Institution Admin`

Why these matter:

- they cover auth
- they cover redirects
- they cover onboarding
- they cover invite role changes
- they cover the two main shells
- they cover notifications
- they cover live
- they cover admin access

## 9. Best Way To Use This File During Testing

For any bug:

1. identify the platform
2. identify the role
3. find the screen or surface above
4. confirm the previous screen was correct
5. confirm the way the user got there was correct
6. confirm the next likely screen is also correct

That avoids a very common silly-cow QA mistake:

- reproducing the right screen
- but through the wrong route, wrong role, or wrong platform path
