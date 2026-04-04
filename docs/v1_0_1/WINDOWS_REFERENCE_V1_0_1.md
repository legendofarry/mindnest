# MindNest Windows Guide

Version: `1.0.1`  
Last updated: `2026-04-02`

## What Is Different On Windows

Windows is not a straight clone of web.

Important realities:

- some Firebase flows use Windows-specific workarounds
- polling/read behavior matters more
- stale binaries can mislead testing
- `Live` is intentionally removed from Windows for now

## Windows Testing Rules

### Always Use The Correct Build

Use the repo-driven Windows testing flow, not an old installed package.

If the app behavior does not match current source, confirm you are not running:

- an old packaged WindowsApps install
- a stale old release build

### Live Is Removed

This is intentional, not a bug.

Expect:

- no Windows live workspace in main navigation
- live routes blocked or redirected appropriately

### Quota / Read Sensitivity

Windows deserves extra attention for read-heavy screens.

Especially watch:

- background polling
- notification badge reads
- any list or shell badge that refreshes too often

If web is fine but Windows says quota exceeded, assume Windows request behavior is suspect before blaming the whole backend.

### Shell Stability

Windows counselor workflows should not:

- jump into a different shell unexpectedly
- visually reload the sidebar when changing between direct tools
- require hot reload tricks to “look right”

### Terminal Noise

Some warnings are dependency noise, but these are real bugs and should be treated seriously:

- `RenderFlex overflowed`
- repeated accessibility bridge churn that follows layout failure

## Best Windows Regression Checks

- correct local build launched
- no live entry points remain
- counselor dashboard/sessions/availability stay in one shell
- notifications open in-place where intended
- no polling-heavy screen quietly spikes reads
