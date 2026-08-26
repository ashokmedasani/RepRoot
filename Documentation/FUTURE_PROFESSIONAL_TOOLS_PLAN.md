# Future Professional Tools Plan

**Status:** Future product plan — not implemented  
**Recorded:** August 11, 2026  
**Scope:** RepRoot website, with limited navigation support from the mobile application

> This document records a proposed future design. It does not describe current product behavior, active plan entitlements, or available billing features. The current source code remains the source of truth until these items are implemented and validated.

## Purpose

RepRoot may add paid, website-focused tools that help professionals take their information outside the normal workspace and establish a public professional presence.

The first proposed tools are:

1. **Export Center** — advanced data exports and a temporary export locker.
2. **Public Portfolio** — a controlled public professional page.
3. **Additional appearance themes** — optional visual themes for paid plans.

These tools should not be mixed into Plan and Billing. Billing explains and manages a subscription; Professional Tools is where entitled users use the features included with that subscription.

## Navigation Decision

Add a primary website navigation item named **Professional Tools**. Place it near the other professional workspace features, preferably between Resources and Profile or Settings.

Recommended routes:

- `/professional/tools`
- `/professional/tools/exports`
- `/professional/tools/portfolio`

Recommended structure:

```text
Professional Tools
├── Export Center (Pro and Premium)
│   ├── Create Export
│   └── Export Locker
└── Public Portfolio (Premium)
    ├── Setup
    ├── Design
    ├── Preview
    └── Publish
```

### Why this should not be under Settings

Settings should remain focused on account configuration, security, notifications, appearance, legal information, and billing. Exporting records and publishing a portfolio are work activities, not account preferences.

### Why the title is “Professional Tools”

The title describes what the area contains without making the navigation sound like an advertisement. Avoid names such as “Premium Benefits,” because the page must remain understandable to Free users who see locked feature previews.

## Professional Tools Landing Page

The landing page should use clear tool cards. Each card should explain:

- What the tool does.
- Which plan includes it.
- Whether the current account can use it.
- What happens if access ends.
- The next available action.

Supported card states:

- **Available** — the account can open and use the tool.
- **Locked** — the plan does not include the tool; show a concise explanation and an upgrade action.
- **Access ending** — a cancellation or downgrade is scheduled; show the access end date and retention policy.
- **Temporarily unavailable** — the feature or a required service is unavailable; do not present it as a plan restriction.

Free users may see these cards as feature previews, but they must not be able to bypass restrictions by navigating directly to a tool URL.

## Export Center

### Intended availability

- **Free:** basic account-data portability only, where legally or operationally required.
- **Pro:** advanced exports and Export Locker.
- **Premium:** advanced exports and Export Locker.

The exact plan matrix must be confirmed only when the feature is ready. This document must not update the current pricing page or backend plan limits.

### Create Export workflow

The professional should be guided through a single export workflow instead of finding unrelated export buttons across the application.

#### Step 1: Choose scope

Potential scopes include:

- One client.
- Selected clients.
- One or more groups.
- All clients.
- Professional workspace information.
- Templates and submitted records.
- Resources and references.
- Meetings and reminders.
- Payment records that the professional is permitted to export.

#### Step 2: Choose information

Show only information that exists for the selected scope and that the authenticated professional is authorized to access. Private system metadata, secrets, other professionals’ information, and operator-only records must never be exportable.

#### Step 3: Choose format

Candidate formats:

- ZIP package.
- CSV.
- Excel workbook.
- PDF summary.

The first implementation should support only formats that can be generated reliably and safely. More formats can be added later without changing plan architecture.

#### Step 4: Review and create

Before creating the export, show:

- Selected scope.
- Included record types.
- File format.
- Estimated size when available.
- Applicable retention and privacy notice.

Large exports should run as background jobs. The UI should display queued, processing, completed, failed, and expired states without creating duplicate jobs through repeated taps.

### Export Locker

The Export Locker is a temporary download area, not permanent storage.

Recommended information:

- Export name.
- Scope.
- Format.
- Requested date.
- Completion date.
- File size.
- Status.
- Expiry date.
- Download and delete actions.

Recommended initial retention: **30 days after successful generation**. Deleting or expiring an export artifact must never delete the original client or professional data from RepRoot.

Existing export actions elsewhere in the website should eventually become shortcuts that open the Export Center with the relevant scope preselected. They should not become separate export implementations.

### Export downgrade behavior

When a Pro or Premium account moves to Free:

1. Advanced export creation remains available only until the paid access period ends.
2. The UI shows the exact access end date.
3. Completed export artifacts remain downloadable only for their existing retention period.
4. Re-upgrading during that period restores entitled access.
5. At expiry, only generated export files are removed; original application records remain governed by normal retention and account rules.
6. Basic account-data portability must not be blocked solely to force a subscription upgrade.

## Public Portfolio

### Intended availability

- **Free:** locked preview.
- **Pro:** not included in the initial proposal.
- **Premium:** setup, preview, and publication.

The portfolio should use its own publication model. It must not automatically expose the private professional profile.

### Portfolio workflow

#### Setup

The professional explicitly selects and enters public information, such as:

- Display name.
- Professional title.
- Short introduction.
- Professional categories.
- Services or areas of work.
- General location or service area.
- Contact or enquiry preference.
- Approved social or professional links.
- Public resources or credentials the professional chooses to display.
- Profile and cover media intended for public display.

Client records, private notes, payment information, private contact information, internal activity, and unpublished profile fields must never be included automatically.

#### Design

Begin with one reliable, responsive, accessible design. Additional portfolio designs can be added later. A small number of polished designs is preferable to several incomplete themes.

#### Preview

Preview must clearly distinguish unpublished changes from the public version. The professional should see the desktop and mobile presentation before publishing.

#### Publish

Publishing must require an explicit action and confirmation. Recommended public URL:

`https://rep-root.com/professionals/<public-slug>`

The public slug must be unique, normalized, protected against reserved words, and changeable through a controlled process. Public pages require abuse reporting, privacy controls, and the ability for operators to unpublish content when necessary.

### Portfolio downgrade behavior

When Premium access ends:

1. Keep the portfolio published until the paid period ends.
2. Unpublish it when paid access expires.
3. Preserve the private portfolio draft for an initial proposed grace period of **90 days**.
4. Show a neutral unavailable page at the former public URL; do not expose the reason for unavailability.
5. Re-upgrading during the grace period restores editing and allows republishing after review.
6. After the grace period, archive or remove portfolio-specific draft data according to the final retention policy, without deleting the professional’s normal account data.

## Appearance Themes

Appearance remains under **Settings → Appearance** and should not be moved into Professional Tools.

Proposed future entitlement:

- **Free:** default/system presentation and standard light theme.
- **Pro:** additional professional themes.
- **Premium:** all Pro themes plus any Premium-only designs introduced later.

Theme availability must be enforced through backend entitlements. A hidden or disabled mobile/web control is not sufficient authorization.

If a paid theme is active when access ends, the application should fall back safely to an included theme while preserving the user’s previous preference for possible restoration after re-upgrade.

## Mobile Application Behavior

The initial proposal does not reproduce Export Center or Portfolio management in Flutter.

Under **More → Professional Tools**, mobile may show:

- Export Center — “Available on the website.”
- Public Portfolio — “Available on the website.”

Each action should open the exact HTTPS website route, not a generic homepage. The website should use its normal secure authentication flow and an allowlisted return destination. Authentication tokens, session values, passwords, or private identifiers must never be placed in URLs.

Mobile should accurately show locked, available, or access-ending states using entitlements returned by the backend.

## Backend Entitlement Model

Proposed capability identifiers:

- `advanced_exports`
- `export_locker`
- `public_portfolio`
- `portfolio_publish`
- `premium_themes`

The exact names may change during implementation, but access should be capability-based rather than scattered plan-name comparisons.

Required principles:

- The backend is the source of truth for authorization.
- Premium inherits relevant Pro capabilities unless deliberately excluded.
- Web and mobile consume the same entitlement response.
- Direct API and route access must be rejected when entitlement is absent.
- Expiry and scheduled cancellation dates use server-side subscription state.
- UI locks explain access but are not treated as security controls.
- Export jobs and portfolio publication actions require authenticated professional ownership checks.

## Suggested Implementation Phases

### Phase 1: Product structure

- Add the Professional Tools navigation and landing page.
- Add locked and available card states.
- Add route guards without implementing tool actions.

### Phase 2: Entitlements

- Establish backend capability definitions.
- Return capabilities consistently to website and mobile.
- Test upgrades, cancellation periods, expiries, and downgrades.

### Phase 3: Export Center

- Define safe export scopes and field allowlists.
- Implement background export jobs.
- Add artifact storage, expiry, download authorization, and deletion.
- Convert scattered export buttons into Export Center shortcuts.

### Phase 4: Public Portfolio

- Add separate portfolio data and publication state.
- Build setup, preview, and publish workflows.
- Add public slug routing and privacy safeguards.
- Add operator moderation and unpublishing support.

### Phase 5: Mobile handoff

- Add Professional Tools cards to More.
- Add secure website deep links.
- Display backend-provided entitlement and access-ending states.

### Phase 6: Validation

- Authorization and cross-account isolation testing.
- Export content and deletion verification.
- Portfolio privacy and unpublished-field testing.
- Upgrade, cancellation, downgrade, retention, and re-upgrade testing.
- Responsive website and mobile handoff testing.
- Accessibility and error-state review.

## Acceptance Criteria

The future feature set should not be considered complete until:

1. Professional Tools is a separate website workspace area.
2. Plan and Billing contains subscription management, not tool workflows.
3. Backend entitlements control all restricted routes and APIs.
4. Exported information is limited to records owned by the authenticated professional.
5. Generated export files expire without deleting original records.
6. Portfolio publication is opt-in and separate from the private profile.
7. No client or private professional data is published automatically.
8. Downgrade and cancellation behavior is clear before the user confirms a change.
9. Mobile opens exact website tool routes without placing credentials in URLs.
10. Current pricing and billing displays are updated only after the features are implemented and verified.

## Decisions Required Before Implementation

- Final entitlement allocation between Pro and Premium.
- Export formats included in the first release.
- Export artifact retention duration.
- Portfolio draft retention after downgrade.
- Initial public portfolio fields.
- Public slug reservation and moderation rules.
- Whether portfolio enquiry submissions use an existing lead form or a dedicated controlled flow.
- Which additional appearance themes are included in each paid plan.

## Explicit Exclusions

This plan does not:

- Change current plan names, prices, limits, or billing behavior.
- Implement Razorpay or another payment gateway.
- Claim that exports, portfolios, or paid themes are currently available.
- Add sensitive configuration to frontend or mobile code.
- Authorize deletion of existing client, professional, billing, or application data.

