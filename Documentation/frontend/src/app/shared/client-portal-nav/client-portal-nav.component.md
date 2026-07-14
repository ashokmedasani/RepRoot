# frontend/src/app/shared/client-portal-nav/client-portal-nav.component.ts

## 2026-07-13 responsibilities

Defines the simplified desktop client navigation for Dashboard, Templates, Trainer Profile, Trainer Chat, and Profile.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the successful Angular production build and relevant backend API regression tests.

## 2026-07-13 production audit

Client sign-out revokes the active backend token before local session cleanup; local cleanup still runs if the network request fails.

## 2026-07-13 visual consistency pass

Aligned this file with the shared Dashboard-style page header, portal navigation, action controls, and unclipped profile-image treatment. Verified at port 4400 with no horizontal overflow and covered by the production Angular build.
