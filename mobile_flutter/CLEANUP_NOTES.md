# Cleanup Notes — Pending Manual Deletion

This file tracks items my sandbox could not delete on its own, so they need a manual delete from your side (right-click delete in Explorer is enough). My environment can create, write, and rename files on this mounted folder, but delete/unlink operations are blocked at the mount level — confirmed this isn't specific to any one file or to Android Studio being open; even a brand-new empty test file couldn't be removed.

## Blocked deletions

### `mobile_flutter/PLEASE_DELETE_ME_old_coachflow.iml`
- **Original name:** `coachflow.iml`
- **Why I wanted to delete it:** Leftover IntelliJ/Android Studio module file from the project's old name ("Coachflow") before it was renamed to RepRoot. It was a byte-for-byte duplicate of `reproot.iml` (same directory) and served no purpose once the project was renamed.
- **What I did instead:** Renamed it to `PLEASE_DELETE_ME_old_coachflow.iml` so it's obviously flagged, and repointed `.idea/modules.xml` to reference `reproot.iml` instead, so this file is no longer used by anything.
- **Status:** Safe to delete manually whenever convenient — nothing references it anymore.

## Other unused/extra items found during the audit (not yet acted on)

These were flagged in the earlier codebase audit as candidates for cleanup once mobile app development picks back up — noting here so nothing gets lost, not urgent:

- **`mobile_flutter/test/live/live_professional_api_test.dart`** — imports a `references_api.dart`/`ReferencesApi` that no longer exists (renamed to `resources_api.dart`/`ResourcesApi`). Skipped by default so it doesn't break `flutter test`, but will fail if the live test suite is ever run. Needs a one-line import/class-name fix, not a deletion.
- **`mobile_flutter/lib/app/router.dart`** — defines an unused route constant `Routes.professionalGroups` that's never wired into the actual routes list. Harmless dead code, safe to remove.
- **`mobile_flutter/windows/`** — a Flutter desktop (Windows) build scaffold that exists even though the app only targets Android (iOS later). Likely a `flutter create` default that was never pruned. Candidate for deletion once confirmed you don't need a Windows desktop build.

Once you've had a chance to review and delete `PLEASE_DELETE_ME_old_coachflow.iml`, this file can be deleted too (or I can, if delete permissions get sorted out by then).

## Temporary preview/reference files (delete once real work is done)

These aren't part of the app itself — just planning artifacts. Delete once the corresponding real work is finished:

- **`mobile_flutter/Mobile_Flutter_Updates_Required_2026-08-03.md`** — the pin-to-pin gap audit comparing the Angular Studio frontend to mobile_flutter. Delete once every gap listed in it has been built and verified in the actual Flutter app (or keep as a historical record if preferred — your call once the work is done).
- **`mobile_flutter/Design_Preview_2026-08-03.html`** — superseded by the folder below. First attempt only varied accent color, not what was asked for; keeping it for now but it's safe to delete.
- **`mobile_flutter/design_previews/plan_1/`, `plan_2/`, `plan_3/`** — three mobile-frame (375px) mockups, same accent blue throughout (color intentionally unchanged), each showing a different button *style system*: plan 1 = rounded/pill (24px radius, no borders on fills), plan 2 = sharp/corporate (4px radius, bordered), plan 3 = elevated/modern (12px radius, soft shadows). Each covers the same button set — primary, secondary, text/ghost, icon, disabled, segmented control, card action button, floating action button, and bottom tab bar — inside a full dashboard layout. Delete this whole `design_previews/` folder once a plan is chosen and the real Flutter theme/widgets are built from it.
