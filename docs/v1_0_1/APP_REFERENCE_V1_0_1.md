# MindNest App Reference

Version: `1.0.1`  
Last updated: `2026-04-02`

## 1. What MindNest Is

MindNest is a Flutter + Firebase mental wellness platform with role-based experiences for:

- `Individual` users
- `Students`
- `Staff`
- `Counselors`
- `Institution Admins`
- `Owner` access for internal/super-admin operations

The app combines:

- authentication and account setup
- adaptive onboarding
- institution joining and invite acceptance
- counselor operations
- student care workflows
- notifications
- privacy controls
- AI-assisted support surfaces
- live audio spaces

## 2. Main Tech/Architecture Snapshot

- Frontend: Flutter
- Routing: `GoRouter`
- State: `Riverpod`
- Backend: Firebase Auth + Cloud Firestore
- Main route map: [app_router.dart](c:/Users/karim/Documents/work/mindnest/lib/core/routes/app_router.dart)
- Core feature folders:
  - `lib/features/auth`
  - `lib/features/onboarding`
  - `lib/features/home`
  - `lib/features/care`
  - `lib/features/counselor`
  - `lib/features/institutions`
  - `lib/features/live`
  - `lib/features/ai`

## 3. Supported Platforms

### Web

Primary broad-surface experience.

- full auth flow
- onboarding
- individual/student/staff flows
- counselor workspace
- institution admin workspace
- live hub and live room
- notification center and detail handling

### Windows

Desktop productivity target with special constraints.

- auth and most workspace flows are supported
- `Live` is intentionally removed on Windows for now
- some Windows flows use platform-specific setup/handoff screens
- quota-sensitive/read-heavy behavior needs extra testing

### Android

Mobile-first runtime.

- core account, onboarding, home, counselor, institution, and live flows should work
- responsive layout testing is important
- shell transitions and overflow handling need attention on smaller screens

### iOS

Target parity should match mobile architecture, but it should be treated as its own validation surface.

- test as separate platform
- verify layout, auth callbacks, notifications, and live flows independently

## 4. User Roles

### Guest / Unauthenticated

Can access:

- login
- register
- forgot password
- email verification entry points

Cannot access:

- protected app dashboards
- counselor tools
- institution admin tools

### Individual

Default direct-consumer role.

Main capabilities:

- complete wellness onboarding
- use the home dashboard
- view counselor directory
- manage personal care flows
- use AI support surfaces
- access privacy controls

Notes:

- can later connect to an institution
- if invited into an institution as student/staff, onboarding completion should carry across where the questionnaire is equivalent

### Student

Institution-linked user role.

Main capabilities:

- accept institution connection/invite
- use student appointments
- use student care plan
- use notifications
- join institution live experiences where supported

### Staff

Institution-linked non-student role.

Main capabilities:

- institution membership
- notifications
- general protected app surfaces allowed by routing

Notes:

- onboarding questionnaire is shared with individual/student

### Counselor

Operations-heavy role.

Main capabilities:

- counselor setup
- counselor dashboard
- appointments
- availability management
- live hub/live room where platform allows
- notifications in counselor shell
- counselor settings/profile
- counselor directory and profile review

### Institution Admin

Institution management role.

Main capabilities:

- institution admin dashboard
- institution admin profile
- admin messages
- invite creation/management
- institution pending/approval flows

### Owner

Special internal access path, not a normal selectable user role.

Main capabilities:

- owner dashboard
- high-level institution/platform oversight

## 5. Authentication and Account Setup

### Login

Main screen:

- [login_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/login_screen.dart)

Expected responsibilities:

- sign in existing users
- respect invite context if user arrived through invite link
- route verified users into the correct workspace

### Registration Entry

Main screen:

- [register_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/register_screen.dart)

Choices:

- `Create Account` for students/staff/general users
- `I'm a Counselor` for counselor-intent registration

Invite-aware behavior:

- registration can preserve invite query parameters
- invited users should continue into invite-compatible setup

### Registration Details

Main screen:

- [register_details_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/register_details_screen.dart)

Responsibilities:

- collect identity/account details
- create account
- preserve invite/role intent context

### Institution Registration

Main screens:

- [register_institution_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/register_institution_screen.dart)
- [register_institution_school_request_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/register_institution_school_request_screen.dart)
- [register_institution_success_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/register_institution_success_screen.dart)

Purpose:

- create institution-admin-led institution setup flow
- move institution applicants through request/success states

### Verify Email

Main screen:

- [verify_email_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/verify_email_screen.dart)

Responsibilities:

- gate protected flows until verification is complete
- preserve invite context

### Forgot Password

Main screen:

- [forgot_password_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/forgot_password_screen.dart)

### Terms / Privacy Surface

Main screen:

- [terms_and_privacy_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/terms_and_privacy_screen.dart)

### Windows Web Setup Required

Main screen:

- [windows_web_setup_required_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/auth/presentation/windows_web_setup_required_screen.dart)

Purpose:

- explain Windows-only handoff/setup constraints
- especially important for routes intentionally unavailable on Windows

## 6. Onboarding

Main screens:

- [onboarding_questionnaire_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/onboarding/presentation/onboarding_questionnaire_screen.dart)
- [onboarding_loading_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/onboarding/presentation/onboarding_loading_screen.dart)

Logic:

- onboarding questionnaire is adaptive
- questionnaire currently applies to:
  - `individual`
  - `student`
  - `staff`
- completion is versioned through `OnboardingQuestionBank.version`

Important behavior:

- onboarding completion is role-aware
- equivalent completion across `individual / student / staff` should carry properly
- onboarding loading screen refreshes profile state before final routing

## 7. Institution and Invite Flows

### Join Institution

Main screen:

- [join_institution_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/join_institution_screen.dart)

Purpose:

- let eligible users join institution flows with join code

### Invite Acceptance

Main screen:

- [invite_accept_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/invite_accept_screen.dart)

Purpose:

- accept or decline institution invite
- validate invite ownership
- validate institution code
- connect account into institution
- route user to appropriate next surface

Important recent behavior:

- individually onboarded users should not be sent back to onboarding after connecting as `student` or `staff`

### Institution Admin

Main screens:

- [institution_admin_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/institution_admin_screen.dart)
- [institution_admin_profile_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/institution_admin_profile_screen.dart)
- [admin_messages_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/admin_messages_screen.dart)
- [institution_pending_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/institution_pending_screen.dart)

Capabilities:

- manage institution members
- review students/staff/counselor state
- send/manage invites
- manage institution-level messaging
- handle institution approval/pending states

### Owner Dashboard

Main screen:

- [owner_dashboard_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/institutions/presentation/owner_dashboard_screen.dart)

Purpose:

- super-admin/internal oversight workflow

## 8. Home and General User Experience

Main screens:

- [home_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/home/presentation/home_screen.dart)
- [privacy_controls_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/home/presentation/privacy_controls_screen.dart)

Likely responsibilities of Home:

- central dashboard for non-admin/non-counselor users
- AI support section
- join-code expansion/join actions
- counselor directory entry
- live hub entry where enabled
- notifications entry
- profile interactions

### AI Support

Main UI surfaces:

- [home_ai_assistant_section.dart](c:/Users/karim/Documents/work/mindnest/lib/features/ai/presentation/home_ai_assistant_section.dart)
- [assistant_fab.dart](c:/Users/karim/Documents/work/mindnest/lib/features/ai/presentation/assistant_fab.dart)

Purpose:

- expose AI support and guidance workflows inside the product experience

## 9. Notifications

Main screens:

- [notification_center_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/notification_center_screen.dart)
- [notification_details_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/notification_details_screen.dart)

Responsibilities:

- all / unread / archived filtering
- detail review
- invite-related actions
- mark read / archive / pin / delete patterns

Counselor-specific note:

- notifications are embedded in the counselor shell middle content lane
- bell should toggle open/closed instead of feeling like a hard page jump

## 10. Counselor Experience

Main screens:

- [counselor_dashboard_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/counselor/presentation/counselor_dashboard_screen.dart)
- [counselor_workspace_shell.dart](c:/Users/karim/Documents/work/mindnest/lib/features/counselor/presentation/counselor_workspace_shell.dart)
- [counselor_setup_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/counselor/presentation/counselor_setup_screen.dart)
- [counselor_invite_waiting_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/counselor/presentation/counselor_invite_waiting_screen.dart)
- [counselor_profile_settings_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/counselor/presentation/counselor_profile_settings_screen.dart)

Core expectations:

- one stable counselor shell
- dashboard, sessions, availability, live, notifications, and profile should feel like one workspace
- top-right bell/profile should behave like in-shell toggles where designed

### Counselor Appointments

Main screen:

- [counselor_appointments_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/counselor_appointments_screen.dart)

Purpose:

- review pending and active appointments
- confirm/complete/cancel/no-show flows
- session handling

### Counselor Availability

Main screen:

- [counselor_availability_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/counselor_availability_screen.dart)

Purpose:

- publish slots
- manage availability grid
- manage open future capacity

### Counselor Directory / Profile

Main screens:

- [counselor_directory_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/counselor_directory_screen.dart)
- [counselor_profile_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/counselor_profile_screen.dart)

Purpose:

- browse counselors
- inspect counselor profile details

## 11. Student Care Experience

Main screens:

- [student_appointments_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/student_appointments_screen.dart)
- [student_care_plan_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/student_care_plan_screen.dart)
- [session_details_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/session_details_screen.dart)
- [crisis_counselor_support_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/care/presentation/crisis_counselor_support_screen.dart)

Purpose:

- review and manage student appointments
- review care plans
- open deeper session detail
- access crisis support/counselor support flow

## 12. Live Audio Experience

Main screens:

- [live_hub_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/live/presentation/live_hub_screen.dart)
- [live_room_screen.dart](c:/Users/karim/Documents/work/mindnest/lib/features/live/presentation/live_room_screen.dart)

Core structure:

- live hub is the discovery/entry surface
- live room is the active audio-room experience

Participant categories used in app logic:

- `Host`
- `Guest` / speaker-type participant
- `Listener`
- `Pending mic requests` as queue/state, not a core participant type

Platform note:

- Windows intentionally does not expose live right now
- web/mobile should remain the primary live surfaces

## 13. Routing and Guarding Rules

At a high level:

- unauthenticated users stay on auth routes
- unverified users are pushed to verify-email flow
- pending invites can redirect into invite handling
- unresolved role users are kept in safe base flows
- incomplete onboarding redirects to onboarding
- counselors are gated through counselor setup before dashboard if needed
- institution admins are routed to institution admin surfaces

Main routing file:

- [app_router.dart](c:/Users/karim/Documents/work/mindnest/lib/core/routes/app_router.dart)

## 14. Shared UI Shells

Important core shell files:

- [desktop_primary_shell.dart](c:/Users/karim/Documents/work/mindnest/lib/core/ui/desktop_primary_shell.dart)
- [desktop_section_shell.dart](c:/Users/karim/Documents/work/mindnest/lib/core/ui/desktop_section_shell.dart)
- [mindnest_shell.dart](c:/Users/karim/Documents/work/mindnest/lib/core/ui/mindnest_shell.dart)
- [auth_desktop_shell.dart](c:/Users/karim/Documents/work/mindnest/lib/core/ui/auth_desktop_shell.dart)
- [auth_background_scaffold.dart](c:/Users/karim/Documents/work/mindnest/lib/core/ui/auth_background_scaffold.dart)

What to care about:

- shell consistency
- no route causing unexpected full-shell flicker
- sidebar/header stability
- toggled panes behaving like panes, not fake page reloads

## 15. Known Areas That Deserve Extra Testing

- role transitions:
  - `individual -> student`
  - `individual -> staff`
  - `individual -> counselor-intent`
- invite acceptance and invite ownership handling
- onboarding completion and redirect stability
- counselor shell toggles:
  - notifications
  - profile
  - direct sidebar routes
- live access by platform
- responsive overflows on Android/iOS
- quota-sensitive behavior on Windows

## 16. Big-Company Product Standard For This App

If MindNest is behaving correctly, it should feel like this:

- one clear shell per role/workspace
- direct navigation, not fake middle pages
- no needless manual refresh after major actions
- route changes should feel stable and intentional
- platform restrictions should be explicit, not buggy
- responsive layouts should degrade gracefully
- notification and profile interactions should feel instant

If the app instead:

- jumps to onboarding after a successful role connection
- opens a different shell unexpectedly
- needs manual refresh to show the correct next state
- throws visible overflows or route flicker

then that is not “just how Flutter works”; it is a product bug and should be treated as one.

## 17. Hidden User State That Changes App Behavior

These profile fields are especially important in testing because they silently change routing and feature access.

- `role`
  - current effective app role
  - can be `individual`, `student`, `staff`, `counselor`, `institutionAdmin`, `other`
- `onboardingCompletedRoles`
  - map of role name -> onboarding version
  - affects whether the app sends a user back to onboarding
- `registrationIntent`
  - used especially for counselor-intent registration
  - `individual + counselor registrationIntent` is treated differently from a plain individual
- `institutionId`
  - empty means not linked to institution
  - non-empty changes what workspace/routes make sense
- `institutionName`
  - used in UI context and invite/institution displays
- `institutionWelcomePending`
  - can affect institution-admin success/pending routing
- `counselorSetupCompleted`
  - counselor cannot be treated as fully ready without this
- `counselorSetupData`
  - stores counselor setup profile/config details
- `counselorPreferences`
  - counselor-specific preference state
- `aiAssistantPreferences`
  - stores AI-related preference state
- `phoneNumber`
  - primary phone
- `additionalPhoneNumber`
  - secondary phone
- `phoneNumbers`
  - normalized list of linked phone values

## 18. Auth and Identity Details That Affect Testing

### Web Sign-In Persistence

- `Remember me` changes Firebase web persistence
- web uses:
  - `LOCAL` persistence when remember-me is on
  - `SESSION` persistence when remember-me is off

This means testing should include:

- tab close/reopen behavior
- browser restart behavior
- sign-in state differences with remember-me on vs off

### Google Sign-In Exists

The app supports Google sign-in in auth flows, not just email/password.

That means testing should include:

- first-time Google sign-in
- existing-account Google sign-in
- collision cases where email already exists under another provider

### Phone Number Rules

The app normalizes registration phone numbers around the Kenya prefix:

- `+254`

And it maintains a `phone_number_registry` to prevent the same phone number being reused across accounts.

That means testing should include:

- primary phone uniqueness
- additional phone uniqueness
- primary/additional phone must not be the same
- account creation with already-used phone should fail cleanly

## 19. Important Route Query Parameters

MindNest is more stateful than a simple page-per-screen app. These query params change behavior:

- `inviteId`
  - identifies an invite context
- `invitedEmail`
  - helps preserve invited account context
- `invitedName`
  - display/support context for invite flows
- `institutionName`
  - used in invite and institution success flows
- `intendedRole`
  - role intended by invite
- `registrationIntent`
  - especially important for counselor-intent signup
- `openJoinCode`
  - can auto-open join-code behavior on Home
- `reason`
  - used by Windows setup/handoff screens
- `notificationId`
  - preselects a notification in notifications flow
- `returnTo`
  - used by in-shell counselor notifications/profile to collapse back correctly

For testing, this means direct URLs matter. You should not test only by clicking through the app.

## 20. Notification Data Model and Behavior Notes

A notification is not just title/body. It also has behavior-driving metadata:

- `type`
- `priority`
- `actionRequired`
- `route`
- `relatedAppointmentId`
- `relatedId`
- `isRead`
- `isPinned`
- `isArchived`
- `resolvedAt`
- `pinnedAt`
- `archivedAt`

### What That Means In Practice

- `type` can change the action buttons and detail logic
- `route` can open a destination directly
- `relatedId` is especially important for invite notifications
- `relatedAppointmentId` is important for appointment-linked notifications
- `actionRequired` should usually feel more urgent/actionable in UI
- `isArchived` should remove the item from normal unread-focused surfaces

### Notification Types Seen In Code

At minimum, the app uses these invite-related types:

- `institution_invite`
- `institution_invite_accepted`
- `institution_invite_declined`
- `institution_invite_revoked`

And there are many appointment/reassignment-related notifications created from the care repository.

## 21. Appointment and Availability Data Details

### Appointment Statuses

Appointment status enum:

- `pending`
- `confirmed`
- `completed`
- `cancelled`
- `noShow`

Extra appointment fields worth testing:

- `rated`
- `ratingValue`
- `counselorCancelMessage`
- `cancelledByRole`
- `attendanceStatus`
- `rescheduledToAppointmentId`
- `rescheduledFromAppointmentId`
- `counselorSessionNote`
- `counselorActionItems`

These are important because the appointment may look “done” in UI while the record still carries meaningful follow-up state.

### Availability Slot Statuses

Availability slot status enum:

- `available`
- `booked`
- `blocked`

Extra slot fields worth checking:

- `bookedBy`
- `appointmentId`

That means slot testing should not only check grid rendering, but also whether slot-to-appointment linkage is preserved.

## 22. Counselor-Specific Hidden Product Logic

### Workflow Toggles Stored At Institution Level

Institution data can enable/disable counselor features through:

- `counselorDirectoryEnabled`
- `counselorReassignmentEnabled`

If these are off, the app should not merely look empty. It should behave intentionally.

### Session Reassignment Exists

This is not a tiny edge feature. The code supports a proper reassignment workflow with statuses:

- `open_for_responses`
- `awaiting_patient_choice`
- `patient_selected`
- `transferred`
- `declined`
- `expired`
- `cancelled`

And reassignment requests also carry:

- response deadlines
- patient choice deadlines
- selected counselor data
- interested counselor list
- transferred appointment linkage

This area deserves separate testing because it has lifecycle logic, urgency, and notifications.

### Counselor Profile Surface Is Richer Than Just Name

Counselor profiles include:

- display name
- title
- specialization
- gender
- session mode
- timezone
- bio
- years of experience
- languages
- rating average
- rating count
- active/inactive state

That means a “profile loads” test is not enough. You should check data completeness and formatting too.

## 23. Care Plan and Ratings Details

### Care Goals

Care goals include:

- title
- status
- createdAt
- updatedAt
- completedAt
- sourceAppointmentId

Key behavior expectation:

- completed goals should remain historically meaningful, not disappear from the mental model

### Public Ratings

Counselor public ratings include:

- appointmentId
- institutionId
- counselorId
- studentId
- numeric rating
- written feedback
- createdAt

Testing should include:

- a rating can only make sense after a real appointment lifecycle
- counselor rating aggregates should reflect underlying ratings data

## 24. Live Data Model Details

### Live Session

A live session includes:

- `status`
  - `live`
  - `paused`
  - `ended`
- `allowedRoles`
- `maxGuests`
- `likeCount`
- `startedAt`
- `endedAt`

That means live access should be tested not only by room existence, but by:

- allowed role enforcement
- paused/live/ended transitions
- max guest/speaker expectations

### Live Participants

Participant kinds:

- `host`
- `guest`
- `listener`

Extra participant fields:

- `canSpeak`
- `micEnabled`
- `mutedByHost`
- `joinedAt`
- `lastSeenAt`
- `removed`

### Live Mic Requests

Mic request statuses:

- `pending`
- `approved`
- `denied`

### Live Comments and Reactions

Both are tracked as their own event records with:

- userId
- displayName
- payload
- createdAt

So if reactions/comments look wrong in UI, that can be either:

- rendering
- ordering
- repeated polling/render churn
- or underlying event creation

## 25. Platform-Specific Behavior Worth Remembering

### Windows

Windows is not just “desktop web in a box”.

- some flows use REST/polling workarounds instead of the nicer native/web listener flow
- `Live` is intentionally cut from Windows for now
- quota-sensitive screens should be treated carefully
- stale local binaries vs packaged app confusion can produce false debugging signals

### Web

Web is currently one of the clearest surfaces for routing/auth testing because:

- auth persistence is explicit
- live is supported
- counselor shell changes are easy to observe
- direct route/query testing is practical

### Android / iOS

Mobile testing should emphasize:

- small-width overflows
- short-height overflows
- shell consistency
- back navigation
- route transitions after setup/invite/onboarding

## 26. Concrete Things That Should Be Verified In Firestore During Testing

When testing, do not only trust UI. Check that these data changes happen correctly:

- after registration:
  - `users/{uid}` exists
  - phone registry entries exist
- after onboarding:
  - `onboarding_responses/{uid_role_version}` exists
  - `onboardingCompletedRoles` is updated
- after invite accept:
  - user `role` changes
  - `institutionId` and `institutionName` update
  - institution member record exists
  - invite status becomes accepted
  - related notifications are read/archived/resolved as intended
- after counselor setup:
  - counselor setup fields reflect completion
- after slot publish:
  - availability slot records exist correctly
- after appointment creation/change:
  - appointment status and slot linkage stay consistent

## 27. What Can Look Fine In UI But Still Be Wrong

These are classic MindNest testing traps:

- user gets to the right page only after manual refresh
- role text changes, but underlying `role` or onboarding state is still stale
- notification appears, but metadata is wrong so details/actions misbehave later
- slot looks open, but linked appointment/booking field is wrong
- shell appears okay, but route actually switched to a different wrapper and flickered
- live room renders, but role permissions are wrong underneath

That is why data-level and route-level verification matter, not just visual checks.
