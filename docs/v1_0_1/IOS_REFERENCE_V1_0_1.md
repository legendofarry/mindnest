n # MindNest iOS Guide

Version: `1.0.1`  
Last updated: `2026-04-02`

## What To Treat Separately On iOS

Even when Flutter code is shared, iOS should not be assumed correct just because Android works.

Separate checks matter for:

- safe areas
- auth callback behavior
- keyboard overlap
- navigation feel
- notification permission behavior
- live audio UX

## iOS Testing Priorities

### Auth

- registration
- login
- verify email routing
- invite-aware flows

### Onboarding

- adaptive questionnaire layout
- loading handoff
- no repeat-onboarding after equivalent role change

### Role Workspaces

- home
- counselor shell
- institution admin
- notifications

### Mobile Layout

Test:

- portrait and landscape where relevant
- notches/safe areas
- long text wrapping
- modal and keyboard behavior

### Live

iOS should be treated as a real live target, not an afterthought.

Check:

- live hub entry
- room join
- reactions/comments/request UI
- role restrictions

## Best iOS Regression Checks

- no onboarding loop after role change
- no layout clipping in tight mobile headers
- shell and back navigation remain stable
- notifications and live still feel native enough
