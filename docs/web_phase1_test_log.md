# Web Phase 1 Test Log

Last updated: 2026-04-02

## Results

| Date | Area | Scenario | Status | Notes |
| --- | --- | --- | --- | --- |
| 2026-04-02 | Live Hub | Removed the `What is Live Hub?` explainer section from the web live hub layout | Fixed in code | The extra explainer card no longer renders in the wide live hub shell, keeping the page focused on the actual live workflow. |
| 2026-04-02 | Counselor Dashboard | Removed `Open notifications` from the dashboard quick routes card | Fixed in code | Quick routes now show only the direct working tools instead of duplicating the notifications entry. |
| 2026-04-02 | Counselor Profile Toggle | Counselor profile now opens and closes inside the same workspace shell on web | Fixed in code | The top-right profile icon now behaves like a proper toggle: first click opens the embedded profile settings pane, second click returns to the prior counselor workspace route. |
| 2026-04-02 | Onboarding Redirect | Web onboarding no longer needs a manual refresh after `Enter MindNest` | Fixed in code | The profile cache signature now includes onboarding completion state, the questionnaire forces a profile refresh after submit, and the onboarding loading screen refreshes profile state before routing onward, so a newly created individual user is not bounced back to step 1. |
| 2026-04-02 | Invite Connect Onboarding | Individually onboarded users no longer get sent back to onboarding after connecting to an institution as a student or staff member | Fixed in code | Shared onboarding completion is now recognized across the individual/student/staff role family, invite acceptance carries equivalent onboarding completion onto the connected role, and the invite accept screen waits for the updated profile before routing onward. |
