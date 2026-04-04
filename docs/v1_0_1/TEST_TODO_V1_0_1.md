# MindNest Test TODO

Version: `1.0.1`  
Last updated: `2026-04-02`

Use this as the working product test checklist for web, Windows, Android, and iOS.

## 1. Global Rules For Testing

- [ ] Always test as the correct role for the scenario
- [ ] Always note platform used: `web / windows / android / ios`
- [ ] Always note if the bug is:
  - visual only
  - route/navigation
  - data/state
  - platform-specific
  - Firebase/backend-related
- [ ] After role-changing actions, confirm no manual refresh is needed
- [ ] After invite actions, confirm role, institution, and onboarding state are all correct

## 2. Auth Testing

### Login

- [ ] Login with valid account
- [ ] Login with invalid password
- [ ] Login with unverified email
- [ ] Login with invite query present
- [ ] Login while already authenticated

### Registration

- [ ] Register as standard account via `Create Account`
- [ ] Register as counselor-intent via `I'm a Counselor`
- [ ] Register while invite context is present
- [ ] Register with existing email
- [ ] Register and confirm routing after success

### Forgot Password

- [ ] Open forgot password
- [ ] Submit valid email
- [ ] Submit invalid/non-existent email

### Verify Email

- [ ] Unverified user is correctly blocked from protected app routes
- [ ] Verified user is released into proper next route

## 3. Onboarding Testing

- [ ] Individual first-time onboarding completes successfully
- [ ] Student onboarding completes successfully
- [ ] Staff onboarding completes successfully
- [ ] Onboarding loading screen routes correctly after completion
- [ ] `Enter MindNest` does not require manual refresh
- [ ] Completed onboarding does not reopen on next login

### Role Transition / Equivalent Onboarding

- [ ] Individually onboarded user accepts `student` invite and is not sent back to onboarding
- [ ] Individually onboarded user accepts `staff` invite and is not sent back to onboarding
- [ ] Onboarding completion map reflects equivalent role completion properly

## 4. Invite and Institution Connection Testing

### Invite Receipt

- [ ] Invite notification appears for invited user
- [ ] Invite belongs only to correct account
- [ ] Wrong account sees “invite belongs to another account” style protection

### Invite Acceptance

- [ ] Student invite accept works with valid institution code
- [ ] Staff invite accept works with valid institution code
- [ ] Counselor invite accept works with valid institution code
- [ ] Invalid institution code is rejected
- [ ] Expired invite is blocked
- [ ] Revoked invite is blocked
- [ ] Already handled invite shows unavailable state

### After Acceptance

- [ ] User role updates correctly
- [ ] Institution ID updates correctly
- [ ] Institution name updates correctly
- [ ] Invite notification is marked resolved/read/archived as intended
- [ ] User lands on correct next route
- [ ] No manual refresh is needed

### Join Institution

- [ ] Join with valid code
- [ ] Join with invalid code
- [ ] Join with expired code
- [ ] Join with maxed-out code
- [ ] Leave institution flow works
- [ ] Leaving institution resets role/state correctly

## 5. Individual / Student / Staff Home Testing

- [ ] Home loads without shell flicker
- [ ] AI section renders properly
- [ ] Privacy controls open correctly
- [ ] Counselor directory entry works
- [ ] Notifications entry works
- [ ] Profile interactions work
- [ ] Join-code inline/open state works correctly

## 6. Counselor Workflow Testing

### Counselor Setup

- [ ] Counselor invite waiting flow works
- [ ] Counselor setup loads when required
- [ ] Completed setup sends user to counselor dashboard

### Counselor Shell

- [ ] Dashboard uses one stable shell
- [ ] Sessions uses the same shell
- [ ] Availability uses the same shell
- [ ] Live uses the same shell where supported
- [ ] Notifications open in the same shell
- [ ] Profile opens in the same shell
- [ ] Bell icon toggles notifications open/closed
- [ ] Profile icon toggles profile open/closed
- [ ] Sidebar does not visually reload/flicker when moving between counselor sections

### Counselor Dashboard

- [ ] Dashboard loads without RenderFlex overflow
- [ ] Quick actions/routes go to real working screens
- [ ] Notification counts display correctly
- [ ] Reassignment feedback/messages behave correctly

### Counselor Appointments

- [ ] Sessions sidebar route opens real appointments surface directly
- [ ] Pending appointments show correctly
- [ ] Confirmed/live/completed counts are correct
- [ ] Appointment actions work
- [ ] Mobile/short-height layouts do not overflow

### Counselor Availability

- [ ] Availability sidebar route opens real manager directly
- [ ] Publish slot works
- [ ] Weekly grid renders correctly
- [ ] Existing slots can be opened/edited
- [ ] Mobile narrow layouts do not overflow horizontally
- [ ] Short-height layouts do not overflow vertically

### Counselor Directory / Profile

- [ ] Counselor directory loads
- [ ] Counselor profile opens
- [ ] Back navigation works

## 7. Notifications Testing

### General Notifications

- [ ] Notification center opens correctly
- [ ] Notification details open correctly
- [ ] Select notification state is stable
- [ ] Empty state looks correct

### Filters

- [ ] `All` filter switches instantly
- [ ] `Unread` filter switches instantly
- [ ] `Archived` filter switches instantly
- [ ] No full loading spinner flash during filter switch

### Actions

- [ ] Mark all read works
- [ ] Archive works
- [ ] Unarchive works
- [ ] Delete works
- [ ] Pin/unpin works
- [ ] Manual refresh icon works where implemented

### Counselor Embedded Notifications

- [ ] Bell opens notifications in middle content area
- [ ] Bell clicked again collapses notifications
- [ ] Previous counselor route is restored correctly after collapse

## 8. Student Care Testing

- [ ] Student appointments screen opens
- [ ] Student care plan screen opens
- [ ] Session details screen opens correctly
- [ ] Crisis counselor support screen opens correctly
- [ ] Route protection blocks wrong roles from protected care screens

## 9. Live Testing

### Live Hub

- [ ] Live hub opens correctly on supported platforms
- [ ] No extra explainer sections appear where intentionally removed

### Live Room

- [ ] Live room opens correctly
- [ ] Host controls render correctly
- [ ] Speaker/guest rendering is correct
- [ ] Listener rendering is correct
- [ ] Request queue behavior is correct
- [ ] Reactions/comments behave correctly

### Platform-Specific Live

- [ ] Web live works
- [ ] Android live works
- [ ] iOS live works
- [ ] Windows does not expose live and instead uses intended fallback/handoff

## 10. Institution Admin Testing

- [ ] Institution admin route opens correctly
- [ ] Institution admin profile works
- [ ] Admin messages screen works
- [ ] Students tab works
- [ ] Staff tab works
- [ ] Counselor-related management areas work
- [ ] Invite creation works
- [ ] Invite revoke works
- [ ] Institution pending state routes correctly

## 11. Owner Testing

- [ ] Owner email routes to owner dashboard
- [ ] Non-owner cannot access owner dashboard
- [ ] Owner dashboard loads without broken guards

## 12. Account and Data Utilities

- [ ] Account export sheet opens
- [ ] Export works without crash
- [ ] Logout works from all major shells

## 13. Web-Specific TODO

- [ ] Signup -> onboarding -> `Enter MindNest` -> dashboard without manual refresh
- [ ] Invite connect on web does not send individually onboarded student/staff back to onboarding
- [ ] Counselor shell toggles feel instant
- [ ] Notification filter changes do not visibly reload
- [ ] Live hub and live room layout look stable on wide screens

## 14. Windows-Specific TODO

- [ ] Run the local repo-built app, not stale packaged binary
- [ ] Live is hidden/unavailable on Windows
- [ ] No quota spike from obvious polling-heavy screens
- [ ] Bell badge polling does not cause free-tier pain once fixed
- [ ] Counselor shell stays visually stable
- [ ] Notifications and direct tools do not require weird restarts

## 15. Android-Specific TODO

- [ ] Launch on real phone
- [ ] Counselor live uses same shell as dashboard/sessions/availability
- [ ] Counselor availability has no overflow on narrow widths
- [ ] Counselor appointments has no short-height overflow
- [ ] Notifications, home, and live work on phone layout
- [ ] Back button behavior is clean

## 16. iOS-Specific TODO

- [ ] Full auth flow
- [ ] Onboarding flow
- [ ] Invite accept flow
- [ ] Counselor workspace shell
- [ ] Notifications
- [ ] Live
- [ ] Responsive safe-area checks

## 17. Regression Hotspots

- [ ] Any role change should preserve correct onboarding state
- [ ] Any major action should not require manual refresh
- [ ] Any shell transition should not look like a full app replacement unless intended
- [ ] Any list filter should feel local and instant where possible
- [ ] Any platform-specific restriction should be explicit, not buggy
- [ ] Any overflow in terminal should be treated as a real bug even if the user can keep tapping through it

## 18. Sign-Off Section

- [ ] Web smoke test done
- [ ] Windows smoke test done
- [ ] Android smoke test done
- [ ] iOS smoke test done
- [ ] Role matrix checked
- [ ] Invite flows checked
- [ ] Onboarding checked
- [ ] Notifications checked
- [ ] Counselor workspace checked
- [ ] Live checked on supported platforms

## 19. Data-State Verification TODO

- [ ] After signup, verify `users/{uid}` exists with correct `role`
- [ ] After signup, verify `phone_number_registry` entries exist for linked numbers
- [ ] After onboarding, verify `onboarding_responses/{uid_role_version}` exists
- [ ] After onboarding, verify `onboardingCompletedRoles` matches expected version
- [ ] After counselor setup, verify counselor setup fields updated
- [ ] After invite accept, verify user `institutionId` and `institutionName`
- [ ] After invite accept, verify `institution_members/{institutionId_uid}` exists
- [ ] After invite accept, verify invite doc status becomes accepted
- [ ] After invite accept, verify related invite notifications become read/resolved/archived
- [ ] After slot publish, verify slot docs have correct `status`, `startAt`, `endAt`
- [ ] After appointment changes, verify slot-to-appointment linkage remains correct

## 20. Route / Query Parameter TODO

- [ ] Test direct route with `inviteId`
- [ ] Test direct route with `registrationIntent`
- [ ] Test direct route with `notificationId`
- [ ] Test direct route with `returnTo`
- [ ] Test direct route with `openJoinCode`
- [ ] Confirm query-driven flows do not lose context after redirects

## 21. Notification Metadata TODO

- [ ] Notification with `route` opens correct destination
- [ ] Notification with `relatedId` resolves correct invite/detail
- [ ] Notification with `relatedAppointmentId` resolves correct session detail
- [ ] `actionRequired` notifications feel urgent/actionable
- [ ] `isPinned` behavior is correct
- [ ] `isArchived` behavior is correct
- [ ] `resolvedAt` is set when a notification is effectively completed

## 22. Feature Flag / Institution Toggle TODO

- [ ] `counselorDirectoryEnabled = false` hides/disables counselor directory flow properly
- [ ] `counselorDirectoryEnabled = true` enables counselor directory flow properly
- [ ] `counselorReassignmentEnabled = false` disables reassignment flow cleanly
- [ ] `counselorReassignmentEnabled = true` enables reassignment flow cleanly

## 23. Persistence and Session TODO

- [ ] Web remember-me ON persists correctly across browser restart
- [ ] Web remember-me OFF behaves like session-only sign-in
- [ ] Google sign-in works for allowed account
- [ ] Google sign-in collision/error states are understandable

## 24. Live Data TODO

- [ ] Live session allowed roles are enforced
- [ ] Host, guest, listener render according to underlying participant kind
- [ ] Mic request pending/approved/denied lifecycle works
- [ ] Paused live session behaves differently from ended/live as expected
