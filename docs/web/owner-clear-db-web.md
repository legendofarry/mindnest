# Owner Clear DB Control

## Purpose

This web-only owner dashboard control exists for local development resets. It gives the owner account a guarded way to wipe MindNest Firestore app data without opening Firebase Console manually.

## Where It Lives

- Owner dashboard
- Visible only on web
- Visible only to the configured owner account

## Safety Guardrails

- The button is shown inside a `Danger Zone` card.
- The action requires typing `CLEAR DB` before it can run.
- Non-owner users are blocked in the repository layer.
- Non-web platforms are blocked in the repository layer.

## What It Clears

Top-level Firestore collections used by the app, including:

- `admin_counselor_messages`
- `appointments`
- `care_goals`
- `counselor_availability`
- `counselor_profiles`
- `counselor_public_ratings`
- `counselor_ratings`
- `institution_catalog_registry`
- `institution_members`
- `institution_membership_audit`
- `institution_name_registry`
- `institutions`
- `live_sessions`
- `mood_entries`
- `mood_events`
- `notifications`
- `onboarding_responses`
- `phone_number_registry`
- `school_requests`
- `session_reassignment_requests`
- `user_invites`
- `user_notification_settings`
- `user_privacy_settings`
- `user_push_tokens`
- `users`

It also clears known nested `live_sessions` subcollections before deleting the parent session documents:

- `participants`
- `mic_requests`
- `comments`
- `reactions`
- `comment_reports`

## What It Does Not Clear

- Firebase Authentication accounts

This is deliberate. The control is meant to clear development data in Firestore, not wipe identity infrastructure.

## Removal Plan

This is a temporary development tool. When owner-side development reset is no longer needed, remove:

- the `Danger Zone` UI from `lib/features/institutions/presentation/owner_dashboard_screen.dart`
- the repository method `clearAllDataForDevelopment()` if it is no longer needed
