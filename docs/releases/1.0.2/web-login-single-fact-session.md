# Web Login Fact Session Behavior

## Version
- `1.0.2`

## Scope
- Web login screen
- Desktop marketing panel on the login experience

## What Changed
- Removed AI-style fact generation from the login marketing card.
- Removed rotating fact behavior during the same login visit.
- Removed the idea of fetching multiple facts during one visit.
- The card now shows one curated MindNest fact for the full login visit.
- A new fact is only selected after the user logs out and lands back on login.

## Current Logic
1. When the web login screen opens, MindNest checks whether this app visit already has an active fact.
2. If a fact already exists for that visit, the same one is shown again.
3. If no active fact exists, MindNest selects one curated fact from the local catalog.
4. The selected fact is saved as the active fact for that running visit.
5. On successful logout, the visit fact is cleared.
6. When login appears again after logout, MindNest chooses a new fact.

## User-Facing Result
- The login screen feels calmer and more intentional.
- Users are not distracted by auto-rotation or fake AI behavior.
- The wording now matches the actual product behavior.

## Before
- Auto-rotating fact feed
- Topic switching
- “Give me another” action
- “Mind-blowing” reaction flow
- AI-style labeling

## After
- One curated welcome fact per login visit
- No AI
- No auto-rotation
- No manual fact switching
- New fact only after logout
