# Institution Web Owner/Admin Updates

Date: 2026-04-20
Version track: 1.0.2
Scope: Web-first institution flows, owner dashboard visibility, admin email-first contact surfaces

## What changed

- Replaced the declined institution resubmission dropdown with a searchable floating picker on web and Windows-style desktop layouts.
- Removed the `School not listed?` action from the declined/resubmit workspace.
- Added institution-claim awareness to school pickers:
  - schools already linked to an institution are disabled
  - claimed schools render in a muted state
  - claimed schools show an `Institution exists` tag
- Applied the same claimed-school protection to the institution registration picker.
- Shifted owner/admin-facing institution contact display toward email-first presentation.
- Owner dashboard institution cards, school-request cards, search, and table contact text now prefer admin/requester email instead of phone-first contact copy.
- Admin workspace invite/member detail views now prioritise email as the primary secondary contact value.

## UX intent

- Prevent duplicate institution claims from the UI instead of letting users hit the error only after submit.
- Make resubmission clearer: search, pick, resubmit, done.
- Keep owner/admin records aligned with the current product direction that institutions are managed by verified email rather than mobile number.

## Notes

- Existing data may still contain legacy phone fields for older records, but the updated owner/admin presentation now favours email wherever available.
- Formatting and analyzer validation were attempted after the changes, but the commands timed out in the current environment.
