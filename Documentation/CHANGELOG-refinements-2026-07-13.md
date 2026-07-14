# Targeted workflow and UI refinements — 2026-07-13

## Reliable chart hover values

- Reproduced the missing canvas tooltip on the live trainer dashboard.
- Line, bar, and doughnut renderers now expose an explicit HTML hover value using Chart.js nearest-element detection, while retaining native tooltips.
- Hover overlays are accessible, theme-aware, kept stable in the DOM to avoid Chart.js resize loss, and cleared when the pointer leaves or the page scrolls.
- Verified visually on port 4400 and through the Angular production build.

## Hover, attention KPI row, and client activity placement

- Chart panels now provide visible border/shadow feedback without moving the canvas, while Chart.js bars, points, and slices retain detailed hover tooltips.
- Client Tracking Center keeps its two graphs in one row and moves immediate attention values into a separate responsive KPI row.
- Trainer client profiles now show Client Activity directly above private Trainer Notes.
- Verified through the Angular production build, 9 backend workflow tests, Django checks, migration drift checks, and live port 4400 inspection.

## Stable storage gauge and analytical dashboard follow-up

- Trainer storage now uses a session-stable request, configurable 100 MB default quota, configurable 15-minute backend cache, and accessible used/quota gauge.
- The Client Action Center is now the Client Tracking Center, with Chart.js priority/status views, an exact-action list, and the existing fixed-height activity queue.
- Shared line, bar, and doughnut renderers use the full analytical-panel language from the referenced hospital page: 330px plots, clear headings/subtitles, stronger tooltips, theme colors, and no graph scrollers.
- Verified with 9 Django workflow tests, Django checks, migration drift checks, the Angular production build, trainer navigation on port 4400, and a seeded client dashboard with 10 rendered charts.

## Visual follow-up

- Simplified trainer-search results to name and code only.
- Added a visible group-registration URL matching the Main Form link treatment.
- Removed reference-library internal scrolling and corrected multiline text-reference formatting.
- Unified Profile and My Account photo/image presentation without a cover band.
- Explicitly aligned Client Actions beside Chat.
- Corrected Security to display the existing `trainer_id` as the current trainer code.

## Trainer authentication and dashboard

- Completed trainer profiles now route from login directly to `/trainer/dashboard`; incomplete profiles continue to `/trainer/profile-setup`.
- The Schedule Overview contains only total pending, due within 24 hours, due within 7 days, total completed, and completed in the last 7 days. The 24-hour value is emphasized.
- Upcoming schedules are ordered by the nearest date/time and rendered in the shared fixed-height list with internal scrolling.

## Client onboarding

- Public leads remain an enquiry workflow: public lead submission, trainer review, approval, group selection, and account creation.
- Group registration is a separate known-client workflow. Each group has a shareable registration URL that fixes the destination group and collects universal plus group-specific fields before trainer review.
- Manual client creation is available from a selected group and the Forms & Groups overview. A group route preselects and locks that group; the overview auto-selects only when one group exists.
- Manual and group-registration conversions generate a read-only internal reference ID, enforce trainer-scoped username uniqueness, create a temporary password, optionally email credentials, and require a password change on first login.

## Shared interaction patterns

- `ConfirmationDialogComponent` and `ConfirmationDialogService` provide one action-specific confirmation contract for delete, approve, warning, send, archive, and status-changing operations.
- Dialogs include an icon, action title, exact target, impact text, cancel, and confirm controls.
- `FixedHeightListComponent` centralizes the approximately-five-row, fixed-height, internally scrollable list pattern for schedules, requests, recent records, and reference rows.

## References

- Search and Create Category now share one responsive toolbar row.
- Category rows show name, description, subcategory count, reference count, expansion, edit, and confirmed delete actions.
- Version 1 plan limits are configured through `COACHFLOW_PLAN_LIMITS`; total references default to 100, categories to 10, and subcategories per category to 5.
- The page prominently reports references used, disables Add Reference at the total limit, and shows the Version 1 limit message without plan upselling.

## Trainer profile and Security

- The trainer profile now uses one professional identity section and a restrained sectioned layout with one profile photo and no cover banner.
- Existing public/private visibility is preserved and extended to headline, training style, specializations, experience, languages, certifications, images, and links. Preview as Client uses the same view and omits private sections.
- Settings now exposes one Security page containing Trainer Code, current/new/confirm password fields, and support-only trainer-account deletion guidance. Trainer code was removed from My Account.

## Client portal

- Find Trainer opens a bounded modal; results cannot expand the login page. A selected trainer returns to the login form and can be changed.
- Successful client login routes to a real dashboard with five KPIs, fixed-height upcoming schedules, and due-within-24-hours emphasis.
- Assigned-template graphs reuse the shared graph engine, group results by template, omit empty datasets, render one full-width graph per row without an internal scrollbar, and include value/date-time/category tooltip metadata.
- Desktop navigation now mirrors the trainer portal at a simpler scale: Dashboard, Templates, Trainer Profile, Trainer Chat, and Profile.
- The former My Details experience is a single Client Information profile section with identity, account, group, joined date, status, reference, and registration-form answers in a clean view/edit pattern.
- The client Trainer area conditionally adds Additional Details after Chat when trainer-shared information exists; trainer profile photos use a corrected crop and broken-image fallback.
- Group Recent Approved Users renders its compact five-user summary without an internal list scrollbar.

## Client Action Center

- Pending client-submitted profile edits now appear directly below the identity section on the trainer's client page.
- Trainer Dashboard Schedule Overview is now Client Action Center, preserving all schedule KPIs while adding Profile Edits Awaiting Review.
- The combined Client Activity Queue switches between fixed-height schedule and profile-edit lists. Edit activities include client, group, request time, changed-field count, client note, and direct review access.
- The existing upcoming-reminders endpoint now aggregates pending profile edits without changing database models or replacing working APIs.
- Trainer client pages now provide Client Workspace, Chat, and Actions as three separate peer sections. Chat is full-width and account controls are isolated in Actions.

## Backend architecture and migration

- `GroupRegistrationSubmission` stores the known-client group-registration workflow independently of `LeadSubmission`.
- `ClientAccess` now supports nullable lead sources, group-registration sources, manual sources, onboarding method, and a unique internal reference ID.
- Migration `0021_manual_and_group_client_onboarding` creates and backfills the new schema.

## Verification

- Django system check: passed.
- Django migration drift check: no changes detected.
- Accounts API regression suite: 8 tests passed.
- Angular production build: passed cleanly after aligning realistic style budgets and declaring the audited PDF/canvas export dependencies.
- Port 4400 health check: HTTP 200, CoachFlow title returned.

## Final production-readiness pass

- Dashboard headers now match the Trainer Profile structure. The Client Action Center presents three priority cards and a compact totals strip instead of six equal KPI blocks.
- Trainer photos use the same larger fitted box in Profile and My Account; the client-facing Trainer section uses the same crop behavior.
- Trainer-managed Additional Details normalize legacy rows, update optimistically, roll back on failure, and explicitly refresh after asynchronous confirmation. Removal was verified end-to-end in the port 4400 browser and database.
- The complete current profile visibility contract is preserved. Legacy gallery, website, social, and video values are bridged into client-visible Images and Links only when those sections are public.
- Client logout and password change revoke server tokens. Public authentication, OTP, directory, and registration endpoints now use scoped throttling.
- Production refuses the development secret and console email backend; HTTPS/HSTS/cookie headers, Redis cache, durable S3-compatible media, and upload limits are supported through environment configuration.
- Frontend Excel export moved from vulnerable `xlsx` to `write-excel-file`; frontend, mobile, and Python dependency audits report zero known vulnerabilities.
- No new migration was required for this final pass. The existing onboarding migration remains `0021_manual_and_group_client_onboarding`.

## Trainer Profile parity notes

- Current planned sections reflected to clients: profile image, public headline, location, About Me, professional focus, training style, specializations, experience, languages, certification, Images, and Links.
- Private sections are excluded from the client payload and client preview.
- One model-level limitation remains: certification is currently one structured certification record, while the product language says “Certifications.” Supporting multiple structured certification records would require a future schema and migration; additional certificate images can currently be shown through Images.

## Overdue schedule follow-up

- Trainer Client Action Center now has four organized priority values: Overdue, Due Within 24 Hours, Due Within 7 Days, and Client Updates.
- Overdue schedules use a distinct red state and are grouped above chronologically ordered upcoming schedules in the fixed-height queue.
- Client Dashboard retains five main KPIs and adds overdue information inside the Schedules section, with separate Overdue and Upcoming groups.
- Due-within calculations now represent future schedules only; overdue records are no longer included in the 24-hour or 7-day counts.
- The eight-test backend suite and clean Angular production build pass after the change. No migration was required.

## Full visual consistency and route audit

- Every trainer portal route now supplies the same Dashboard-style eyebrow, title, meaningful subtitle, divider, action alignment, sidebar, and 80rem workspace contract.
- Forms & Groups no longer overrides shared primary, secondary, and ghost button sizing, so page-header actions match Profile, Clients, Groups, and Templates.
- Removed obsolete global LinkedIn-style hero and top-shell CSS. The stale negative photo margin was the cause of the clipped trainer image.
- Trainer Profile and My Account now use the same 8.5rem square, center-cropped photo treatment with the image fully contained in its panel.
- Added a reusable Client Page Shell and converted Client Dashboard, Profile, Templates, Trainer Profile, and Trainer Chat to the same desktop sidebar and page-header structure as the trainer portal.
- Client navigation highlights Trainer Profile and Trainer Chat independently. The mandatory password-change screen intentionally remains a focused access workflow.
- Trainer login, signup, and password recovery now use the shared eyebrow hierarchy while retaining their centered access-page layout.
- Protected trainer and client routes now redirect unauthenticated visitors to the appropriate login page before protected components load.
- Live route review covered every trainer, client, authentication, legal, and public-form route at port 4400. No reviewed page produced horizontal overflow or broken images.
- Verification: Angular production build passed, 8 backend tests passed, production-mode Django deployment check passed, and `npm audit --omit=dev` reported zero vulnerabilities.
- No database migration was required for the visual consistency pass.

## Trainer total data usage

- The shared trainer sidebar now displays Total Data Usage immediately above Sign Out on every trainer page.
- The authenticated calculation includes trainer-owned database records, client content, profile media, and reference uploads, with a 60-second cache.
- The API returns total, database, and uploaded-file byte counts; the sidebar formats the total into a compact human-readable value.
- Verification: 9 backend tests pass, the Angular production build passes, and the seeded trainer displays `561 KB` in the live port 4400 preview.
- No database migration was required.

## Interactive analytics values

- Chart values remain hidden in the normal view and appear only during interaction.
- Hovering a bar, point, or doughnut segment opens a blue value label beside the pointer.
- Clicking pins the selected value; clicking it again or scrolling clears the pinned state.
- Doughnut interactions include category, exact value, and percentage. Line interactions preserve date/time context.
- No new npm dependency, API change, or database migration was introduced.
- Verification: Angular production build passed; the live trainer dashboard confirmed values are absent at rest, visible on hover, and retained after click-to-pin.

## Global user-facing error pages

- Added a theme-aware shared error page for 404, access, network, server, and unexpected frontend failures.
- Added centralized HTTP failure routing while preserving local validation messages and existing `401` login handling.
- Added a global Angular error handler that logs technical details but exposes only safe recovery guidance to users.
- Added retry, safe-home, back, and Support guidance actions.
- No API, database, or migration changes were required.
- Verification: Angular production build passed; live browser checks confirmed wildcard 404 routing, API GET 404 routing, the default 500 page, no horizontal overflow, and correct recovery controls at port 4400.

## Admin Portal Phase 1 and Finance

- Added isolated internal authentication, seeded role/permission foundations, protected aggregate Dashboard, separate Finance page, and read-only Audit Logs.
- Added immutable trainer `TRN-…` references. Audit targets display `username · TRN-reference` for trainers and `trainer_username:CL-reference` for clients.
- Added safe finance-ledger architecture without storing payment credentials or inventing revenue before a provider is configured.
- Added migrations `accounts.0022` and `admin_portal.0001`/`0002`.
- Verification: 16 backend tests and the Angular production build pass; live port 4400 review covered login, Dashboard, Finance, and Audit Logs with no horizontal overflow.
