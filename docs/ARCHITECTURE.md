# MindNest Architecture (Flutter + Firebase)

## Stack

1. Flutter app (mobile-first)
2. Firebase Auth for identity and token lifecycle
3. Cloud Firestore for core app data
4. Netlify (separate web admin app later)

## Project Structure

`lib/` is organized by feature:

1. `app/`: theme and app root
2. `core/routes/`: router and route guards
3. `features/auth/`: auth data + UI
4. `features/institutions/`: institution membership data + UI
5. `features/home/`: dashboard shell

## Data Model (V1 Base)

### `users/{uid}`

1. `email`: string
2. `name`: string
3. `role`: `individual | student | staff | counselor | institutionAdmin | other`
4. `institutionId`: string | null
5. `institutionName`: string | null
6. `createdAt`: timestamp
7. `updatedAt`: timestamp

### `institutions/{institutionId}`

1. `name`: string
2. `joinCode`: string (unique, uppercase)
3. `createdBy`: string (uid)
4. `createdAt`: timestamp

### `institution_members/{institutionId_uid}`

1. `institutionId`: string
2. `userId`: string
3. `role`: `student | staff | institutionAdmin`
3. `joinedAt`: timestamp
4. `status`: `active | removed`

### `counselor_invites/{inviteId}`

1. `institutionId`: string
2. `institutionName`: string
3. `counselorName`: string
4. `counselorEmail`: string
5. `role`: `counselor`
6. `status`: `pending`
7. `invitedBy`: string (uid)
8. `createdAt`: timestamp

### `user_invites/{inviteId}`

1. `institutionId`: string
2. `institutionName`: string
3. `invitedName`: string
4. `invitedEmail`: string
5. `intendedRole`: `student | staff | counselor`
6. `status`: `pending | accepted | declined | revoked`
7. `invitedBy`: string (uid)
8. `acceptedByUid`: string (optional)
9. `createdAt`: timestamp

### `onboarding_responses/{uid_role_version}`

1. `userId`: string
2. `role`: string
3. `version`: int
4. `answers`: map<string,int>
5. `submittedAt`: timestamp

## Auth/Access Rules

1. Unauthenticated users can only access login/register/reset routes.
2. Authenticated users can complete pre-verification onboarding routes:
   `post-signup`, `join-institution`, `institution-admin`, `verify-email`.
3. Verified users can access app routes.

## Registration Architecture

1. Individual signup asks: full name, email, password.
2. Immediately after signup, user chooses:
   - `Join institution with code`
   - `Continue as individual`
3. Joining with code allows only `Student` or `Staff`.
4. Counselor role is not selectable in user join flow.
5. Institution signup creates:
   - Institution Admin account
   - Institution record + shareable join code
6. Admin can create counselor invite records from the admin panel.

## Routing Priority

1. Not signed in: login/register screens.
2. Signed in, not email-verified: verify screen (with onboarding join-role exceptions).
3. Verified + pending invite: invite-accept screen.
4. Verified + unresolved role: role selection/join step.
5. Verified + role set + onboarding incomplete: onboarding questionnaire.
6. Else: normal dashboard.

## Security Principles

1. Trust Firestore security rules, not client-only checks.
2. Restrict user profile reads/writes to owner.
3. Allow institution writes only for institution admins (custom claim in later phase).
4. Keep moderation actions behind admin/staff roles.
