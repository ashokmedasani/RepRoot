# Admin Portal Security Rules

- No public staff signup.
- Active internal staff profile plus granular permission required by every endpoint.
- Professional/client tokens cannot access Admin APIs.
- Admin tokens use session storage and are separate from portal tokens.
- Finance and Audit navigation is permission-aware, but backend checks remain authoritative.
- Audit records are immutable through the model and have no delete/update API.
- Finance stores ledger metadata only; never full card/payment credentials.
