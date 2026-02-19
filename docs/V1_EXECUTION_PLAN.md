# MindNest V1 Execution Plan

This repository now implements the first build slice:

1. Auth
2. Institution join by code

The remaining V1 scope should be built in this exact order:

1. Mood Tracker
2. Self Assessment
3. Resource Library
4. Appointment Booking
5. Notifications
6. Forum
7. Admin dashboard polish

## Sprint Structure

Use two-week sprints with hard acceptance criteria:

1. `Sprint A`: auth hardening, institution admin creation flow, audit logging
2. `Sprint B`: mood tracker with streak detection and reminders
3. `Sprint C`: assessments engine and scoring
4. `Sprint D`: resources and bookmarks
5. `Sprint E`: booking system with counselor availability
6. `Sprint F`: forum + moderation queue
7. `Sprint G`: QA hardening, analytics, release prep

## Non-negotiables (V1)

1. Enforce email verification before app access
2. Firestore rules deployed before launch
3. App-wide error tracking (Sentry)
4. Backups/export strategy for Firestore and Cloud Storage
5. Terms, privacy policy, and emergency disclaimer in app

## Current Code Status

Implemented:

1. Firebase auth (register, login, reset password, verification gate, logout)
2. User profile persistence in Firestore (`users` collection)
3. Institution join by code and leave flow
4. Post-signup branching: join institution vs continue individual
5. Institution registration flow with auto-created Institution Admin account
6. Institution admin panel for join code sharing and counselor invite creation
7. Router guards with verification + onboarding route enforcement
8. Foundation theme and feature-oriented folder structure
9. Invite-accept flow for invite-first users and existing users
10. Long role-based onboarding questionnaire with completion tracking

Not implemented yet:

1. Mood, assessments, resources, booking, forum
2. Notifications pipeline and analytics
3. Sentry integration
