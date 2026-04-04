# MindNest Role Test Matrix

Version: `1.0.1`  
Last updated: `2026-04-02`

Use this to decide what each role should and should not be able to do.

## Guest / Unauthenticated

Should access:

- login
- register
- forgot password
- verify-email entry points if routed there

Should not access:

- home dashboard
- counselor workspace
- institution admin workspace
- live room protected flows

## Individual

Should access:

- onboarding
- home
- notifications
- privacy controls
- counselor directory
- AI support surfaces

Should be able to do:

- complete onboarding
- remain individual
- join/connect to institution later

Should not be forced into:

- counselor setup
- institution admin dashboard

## Student

Should access:

- home or student-appropriate dashboard flows
- student appointments
- care plan
- notifications
- institution-linked live where allowed

Should be able to do:

- accept student invite
- stay institution-linked

Critical check:

- if already onboarded as individual, student connect should not restart onboarding

## Staff

Should access:

- institution-linked protected app surfaces allowed by routing
- notifications

Critical check:

- if already onboarded as individual, staff connect should not restart onboarding

## Counselor

Should access:

- counselor setup if incomplete
- counselor dashboard
- counselor appointments
- counselor availability
- counselor notifications
- counselor profile/settings
- counselor live where supported

Should experience:

- one stable counselor shell
- no fake middle pages for sessions/availability
- toggle behavior for notifications/profile where designed

Should not be sent to:

- generic individual onboarding after counselor route changes

## Institution Admin

Should access:

- institution admin dashboard
- institution admin profile
- admin messages
- member/invite management
- institution pending flow if approval blocked

Should not be treated as:

- counselor
- generic individual

## Owner

Should access:

- owner dashboard

Should be restricted by:

- owner email/config rules

## Cross-Role Transition Matrix

### Individual -> Student

Expected:

- role changes to `student`
- institution link is added
- onboarding equivalent completion is preserved
- user is not bounced back to onboarding step 1

### Individual -> Staff

Expected:

- role changes to `staff`
- institution link is added
- onboarding equivalent completion is preserved

### Individual -> Counselor Intent

Expected:

- registration intent is stored
- user follows counselor-intent flow
- user is not treated as generic individual for counselor-specific setup gating

### Counselor -> Approved/Ready

Expected:

- counselor setup completes
- user lands in counselor workspace
- counselor shell becomes stable and direct

## Platform Overlay

### Web

Best for:

- invite deep links
- routing
- onboarding transitions
- counselor shell
- live

### Windows

Best for:

- shell stability testing
- route guard behavior
- platform restriction handling

Known special case:

- no live support for now

### Android

Best for:

- compact layout
- touch flows
- back navigation

### iOS

Best for:

- safe-area and mobile-native polish checks
