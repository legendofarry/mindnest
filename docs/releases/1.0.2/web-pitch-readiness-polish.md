# Web Pitch Readiness Polish

## Version
- `1.0.2`

## Scope
- Web login and browser-first entry experience
- Web metadata, manifest branding, and first-load presentation

## Why This Pass Happened
- The browser experience already had strong product depth, but the public-facing entry still behaved more like an internal login than a pitchable product front door.
- Browser metadata was also still using placeholder Flutter starter content, which weakens trust during demos, shared links, and install prompts.

## What Changed

### 1) Desktop login now sells the product better
- Reworked the left-side desktop marketing panel on the web login experience.
- Added a clearer product headline, role chips, workflow highlights, and proof-style metric cards.
- Added direct CTAs for `Create account` and `Register institution`.
- Preserved the curated MindNest fact card, but downgraded it from the whole story to a supporting element.

### 2) Invite context reads more intentional
- Added a dedicated invite-ready message in the desktop marketing panel when a user lands with institution invite context.
- This makes the web journey feel guided instead of generic.

### 3) Browser presentation no longer looks like a starter template
- Replaced placeholder metadata in `web/index.html`.
- Added branded title, description, canonical URL, Open Graph tags, and Twitter preview tags.
- Updated `web/manifest.json` name, short name, description, colors, display mode, and orientation.
- Updated the package description in `pubspec.yaml` so project metadata also reads like MindNest rather than a scaffold.

### 4) First paint now feels branded
- Added a branded loading stage in `web/index.html` that appears before Flutter paints the first frame.
- The loader now matches the web visual direction instead of flashing a blank or generic bootstrap state.

## External Platform Check
- Reviewed the current Netlify SPA rewrite setup and Firebase web configuration before editing.
- No immediate external routing blocker was found for this pass.
- The more obvious credibility gap was branding/metadata, so that became the safest high-impact fix.

## Before
- Desktop login mostly led with a wellness fact card.
- Web metadata still said `A new Flutter project`.
- Manifest naming and title casing were not presentation-ready.
- First-load state relied on the default bare Flutter boot experience.

## After
- Desktop login explains what MindNest does and who it serves.
- Browser tabs, previews, and install metadata now reflect the actual product.
- First load feels branded and intentional.
- The web entry experience is more credible for demos, pitches, and early customer conversations.

## Validation Intent
- Run `dart format` on touched Dart files.
- Run a focused `flutter analyze` pass on the touched web/auth surfaces.
