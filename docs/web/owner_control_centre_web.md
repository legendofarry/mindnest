# Owner Web Control Centre (Phase 1)

## Scope

This document captures the first owner-side web remake pass that expands owner visibility beyond simple institution approve/decline actions.

## Why This Change

Before this pass, owner web mostly showed:

- pending institution requests
- pending school-not-listed requests
- development `Clear DB` action

That was enough for approvals, but not enough for governance or record keeping. The owner needed full institution visibility and a clearer operational overview.

## What Was Added

### 1) Live owner-wide institution records

- New repository stream/getters:
  - `watchOwnerInstitutions()`
  - `getOwnerInstitutions()`
- Both return all institutions (not just pending), sorted by latest meaningful update.

Files:

- `lib/features/institutions/data/institution_repository.dart`

### 2) Owner overview section

Owner dashboard now includes a full overview surface with:

- total institutions
- approved institutions
- pending institutions
- declined institutions
- school request count

### 3) Search + status-filtered records table

Owner can now:

- search institution records by name, catalog id, contact details, or status
- filter records by status (`all`, `pending`, `approved`, `declined`)
- inspect created/updated lifecycle dates in one table

### 4) Recent owner activity stream

Owner now sees a quick operational feed assembled from:

- institution created/requested events
- institution approved/declined events
- still-pending lifecycle updates
- school-not-listed requests

### 5) Existing actions preserved

We kept all existing owner actions intact:

- approve/decline institution
- approve/decline school-not-listed request
- web-only development `Clear DB` danger zone

## UI Direction

The owner workspace now behaves more like a command centre than a queue form:

- overview first
- action queues second
- records + history visible without leaving the screen

This is aligned with how bigger products usually structure operator dashboards: state visibility, records, and actionability in one place.

## Web-First Note

This phase is intentionally web-first. Once validated, the same owner layout pattern can be carried to Windows desktop for parity.
