# Windows Phase 1 Test Log

Last updated: 2026-03-26

## Planned Windows Smoke Tests

- Institution admin registration
- Windows signup CTA opens web
- Windows registration routes redirect to login
- Windows Google sign-in rejects non-existing accounts
- Student login
- Logout
- Forgot password email
- Verify email flow
- Profile modal open/close
- Basic Home interactions
- Session booking and session details
- Live room join/leave
- AI assistant open/use

## Results

| Date | Area | Scenario | Status | Notes |
| --- | --- | --- | --- | --- |
| 2026-03-26 | Auth | Forgot password email for `big.moderator.24.7@gmail.com` | Passed | Firebase Auth `PASSWORD_RESET` request was accepted by the new `mindnest-45772` project. First attempt returned a transient `503` backend error (`Error code: 26`), second attempt succeeded. Inbox/spam delivery still needs manual confirmation by the user. |
| 2026-03-26 | Windows UI | Logout confirm modal on pending-review screen flickered open then closed immediately | Fixed in code | Windows logout confirmation is now opened on the next frame and the dialog barrier is no longer outside-click dismissible on Windows, so the opening click cannot immediately close it. |
| 2026-03-26 | Windows Auth Flow | Verify email, onboarding, institution approval, and counselor setup moved out of Windows | Fixed in code | Windows now routes these incomplete-account states to a simple web handoff blocker page instead of trying to run the workflows locally. |
| 2026-03-26 | Windows Counselor Flow | Counselor invite waiting changed from auto-refresh to manual check | Fixed in code | Windows counselor waiting now uses a manual `Check Again` action and `Open Web` handoff instead of the live invite stream/action panel. |
