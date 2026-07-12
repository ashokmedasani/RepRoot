# Refinements — 2026-07-10 (12 targeted items)

Scoped UI/workflow refinements plus a small, additive data layer. No existing
backend logic was rebuilt; migrations only add tables/columns.

## Database changes (additive)
- **`ClientReminder`** (`client_reminders`) — follow-up scheduler. Fields: `trainer` (FK user), `client` (FK ClientAccess), `title`, `date`, `time` (nullable), `notes`, `status` (`pending`/`done`), `notify_trainer` (bool), timestamps. Powers the dashboard "Upcoming Follow-ups" query (trainer + pending, ordered by date/time).
- **`ProgressEntry`** (`progress_entries`) — trainer-written progress records. Fields: `client` (FK), `trainer` (FK), `title`, `date`, `notes`, `status`, `next_step`, `created_by`, timestamps.
- **`ClientAccess.additional_info_shared`** (bool, default False) — section-level visibility for Additional Information. When true, the whole section is exposed to the client.
- **`TrainerProfile.profile_visibility`** already existed (per-section Public/Private map); now edited from the Profile page instead of My Account.
- Migrations: `0020_*` (reminder/progress/additional_info_shared). Profile visibility/images/links from earlier `0018`–`0019`.

## New / changed endpoints (accounts)
- `PUT trainer/profile/visibility/` — update only `profile_visibility` (`TrainerProfileVisibilityView`).
- `GET|POST trainer/forms-groups/clients/<id>/reminders/`, `PUT|DELETE trainer/reminders/<id>/`, `GET trainer/reminders/upcoming/` (next 5 pending).
- `GET|POST trainer/forms-groups/clients/<id>/progress/`, `PUT|DELETE trainer/progress/<id>/`.
- `ClientAdditionalInfoView` now also accepts `additional_info_shared`.
- `ClientMeView` returns `additional_info_shared` + `shared_additional_info` (whole section when shared).

## Item-by-item
1. **Profile visibility** moved to the read-only **Profile page** (per-section Public/Private toggles saved via the visibility endpoint) + **Preview as Client** mode (shows only Public sections). Toggles removed from My Account.
2. **Template field limit** — builder shows "Fields: N / 8", disables Add Field at 8, message "You have reached the maximum of 8 tracking fields for this template." Entry date/time are system fields, not counted.
3. **Follow-up scheduler** — card on the client profile (after Private Notes) + dashboard "Upcoming Follow-ups" (≤5, fixed-height, Open Client / Mark Complete).
4. **Client profile layout** — two tabs: **Client Workspace** (notes, scheduler, change request, activity, assigned templates, additional info) and **Chat**.
5. **Additional Information visibility** — single section-level Private / Shared-with-Client toggle; client sees the section only when shared.
6 + 12. **Assigned references accordion** — new reusable `shared/references-accordion` (YouTube inline, PDF/doc/link Open, text inline, image preview). Used on the trainer template Overview and the client template view; the separate client Resources tab was removed.
7 + 8. **Template Overview** — removed Recent Entries; per-numeric-field stats (count/avg/latest/min/max via `numericFieldStats` in the graph engine) with a "No tracking data..." message; charts only when data; 2-up grid, last chart full-width when odd, stacked on mobile.
9 + 10. **Template tabs** — Overview / Data Entries / Progress. Data Entries gains a date filter (from/to) and CSV/Excel export.
11. **Progress** — trainer-written timeline (add/edit ProgressEntry); no auto charts.

## Key files
- Backend: `accounts/models.py`, `serializers.py`, `views.py`, `urls.py`, migration `0020`.
- Frontend new: `shared/references-accordion/references-accordion.component.ts`.
- Frontend edit: `shared/analytics/graph-engine.ts` (`numericFieldStats`), `pages/trainer/trainer-client-template/*`, `pages/trainer/trainer-client-profile/*`, `pages/trainer/trainer-dashboard/*`, `pages/trainer/trainer-profile/*`, `shared/trainer-profile-form/*`, `pages/trainer/trainer-tracking-template-create/*`, `pages/clients/client-profile/*`, `core/api/forms-groups-api.service.ts`, `core/api/trainer-auth-api.service.ts`.

## Verification
- `manage.py makemigrations --check` → no changes; `manage.py check` → clean; new URLs resolve.
- `ng build --configuration development` → success.
