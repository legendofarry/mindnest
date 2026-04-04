i# MindNest Android Guide

Version: `1.0.1`  
Last updated: `2026-04-02`

## What Android Is Best For

Android is the best place to catch:

- narrow-width layout problems
- short-height overflow issues
- back-navigation mistakes
- route transition roughness
- touch-target problems

## Android Testing Rules

### Prefer Real Device Testing

Real phone testing is better than a sulking emulator for this app.

Why:

- auth callbacks are more realistic
- layout behavior is more trustworthy
- back button behavior matters
- emulator/ADB issues can waste time

### Restart After Fixes

For Android changes, the preferred flow is:

- make fix
- re-run app on real phone

Especially important after:

- router changes
- shell changes
- layout fixes

### Common Android Risk Areas

- counselor availability overflow
- counselor appointments overflow
- shell transition consistency
- notification panel state
- live room layout on smaller widths

### Mobile Copy Discipline

Desktop-sized wording often looks silly on phone.

Test:

- labels
- CTA length
- wrapped chips/buttons
- header rows with actions on the right

## Best Android Regression Checks

- counselor live stays in same shell as counselor dashboard tools
- availability has no horizontal overflow
- appointments have no vertical overflow in compact height
- notifications behave cleanly on mobile widths
- back button returns to sane prior routes
