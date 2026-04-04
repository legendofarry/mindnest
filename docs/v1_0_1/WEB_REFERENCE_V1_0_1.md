c# MindNest Web Guide

Version: `1.0.1`  
Last updated: `2026-04-02`

## What Web Is Best For

Web is one of the cleanest surfaces for testing:

- auth and route guards
- invite deep links
- onboarding transitions
- counselor shell behavior
- notifications
- live hub and live room

## Web-Specific Behaviors

### Session Persistence

Web respects `Remember me`:

- on: local persistence
- off: session persistence

Test:

- close tab, reopen tab
- close browser, reopen browser
- sign in again with remember-me off

### Invite / Deep-Link Testing

Web is ideal for direct URL testing:

- invite URLs with `inviteId`
- notification URLs with `notificationId`
- counselor shell return behavior with `returnTo`
- registration flows with `registrationIntent`

### Onboarding Expectations

Web should not require a manual browser refresh after:

- first onboarding completion
- invite connect changing role
- returning from onboarding loading

If a refresh is needed, that is a state bug.

### Counselor Workspace Expectations

On web, counselor flows should feel like one stable product shell:

- dashboard
- sessions
- availability
- live
- notifications
- profile

The bell and profile icon should behave like proper toggles where implemented, not like jarring page replacements.

### Notifications On Web

Expect:

- filter switches feel instant
- no obvious full-page loading flash between `All / Unread / Archived`
- inline detail review on wide layouts
- metadata-driven actions working from the notification detail side

### Live On Web

Web is one of the main supported live surfaces.

Check:

- live hub opens correctly
- role restrictions are respected
- live room layout is stable
- host/speaker/listener behavior is correct
- comments, reactions, and requests feel coherent

## Best Web Regression Checks

- signup -> verify -> onboarding -> dashboard without refresh
- individual -> invited student connect without onboarding reset
- counselor shell toggle behavior
- notifications metadata routing
- live access by role
