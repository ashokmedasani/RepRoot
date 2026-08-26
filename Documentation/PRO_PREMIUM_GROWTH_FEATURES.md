# RepRoot Pro and Premium Growth Features

Status: product architecture proposal only. These features are not implemented,
enabled, or advertised by the current application.

## Product objective

Paid plans should create measurable professional value in two areas:

1. Operational control: help professionals retain, analyze, export, and reuse
   the information created through their work.
2. Business growth: help professionals present their work publicly and convert
   visitors into structured RepRoot leads.

Plan limits remain sourced from the Django billing catalogue. This document
does not replace or redefine the live plan configuration.

## Recommended entitlement structure

### Free

- Core professional-client workflow
- Basic lead form, client, group, template, resource, and storage allowances
- No bulk data export
- No public portfolio publishing
- No directory listing

### Pro

- All Free workflow capabilities with the live Pro allowances
- Account-owned data export in safe formats such as CSV and ZIP
- Date, client, group, template, and record filters before export
- Export history containing requester, timestamp, scope, status, and expiry
- Optional scheduled account backup after export reliability is proven
- Advanced workflow reporting can be evaluated later

### Premium

- All Pro capabilities with the live Premium allowances
- Public professional portfolio with a stable, unique slug
- Choice of four or five curated, accessible portfolio themes
- Selected professional details, services, links, media, and qualifications
- A public enquiry action connected to an existing active lead form
- Optional RepRoot professional-directory listing
- Explicit marketing consent, preview, publication controls, and moderation
- Custom branding can be considered after the core portfolio is stable

## Portfolio architecture

Do not expose the authenticated `ProfessionalProfile` model or serializer
directly. Create a public publication model containing only approved fields:

- professional owner
- unique public slug
- theme identifier
- draft, review, published, suspended, and archived states
- explicitly selected public fields
- selected active lead form
- directory opt-in and consent timestamp
- moderation status and audit information
- published and last-updated timestamps

The professional must be able to preview the exact public result before
publishing. Client records, private notes, payments, schedules, internal
identifiers, and unpublished contact details must never enter the public
portfolio response.

## Professional directory architecture

Directory publishing must be optional and separate from owning a portfolio.
The public directory should support structured filters such as profession,
service category, language, service mode, and broad service area. Avoid precise
private location data unless the professional intentionally publishes it.

Before launch, include:

- explicit opt-in and easy opt-out
- profile review/moderation
- report-profile and abuse workflows
- rate limiting and bot protection
- search pagination and safe query validation
- image and document validation
- publication and consent audit records
- SEO canonical metadata for published pages
- a clear policy for expired or downgraded Premium memberships

Do not promise automatic marketing reach. A directory creates value only when
it has useful profiles and meaningful visitor traffic.

## Web and mobile responsibilities

Portfolio building, theme editing, publication, export creation, and directory
consent should be managed on the website first. Mobile may show the entitlement
and current status, then open the authenticated website using a short-lived,
server-issued handoff token. It must not pass reusable auth tokens in a URL.

Suggested mobile copy:

> Manage exports and your public portfolio on the RepRoot website.

Mobile should still be able to view export status and portfolio publication
status later, but full editing is intentionally web-first.

## Public lead-form contract

Website and Flutter must receive the same canonical shareable form URL from the
backend. The backend uses `REPROOT_FRONTEND_URL` and returns:

`https://your-domain.com/public/forms/<public-slug>`

The public route must not require professional or client authentication. It
must retain spam controls, input validation, per-IP throttling, and professional
ownership isolation.

## Recommended delivery order

1. Data export with audit, authorization, expiry, and restore testing.
2. One secure portfolio model and one theme, including preview and unpublish.
3. Lead-form connection and portfolio analytics.
4. Remaining curated themes.
5. Directory opt-in, moderation, reporting, and search.
6. Mobile entitlement/status surfaces and secure web handoff.

This order validates paid operational value before depending on a directory
network effect.
