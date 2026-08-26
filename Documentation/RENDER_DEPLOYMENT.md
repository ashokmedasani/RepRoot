# Render Frontend Deployment

RepRoot uses Render only for the Angular static website. The Django API is
deployed separately and is not configured by `render.yaml`.

## Deployment source

- Service: `reproot-web`
- Repository branch: `Test`
- Root directory: `frontend`
- Build command: `npm ci && npm run build:render`
- Publish directory: `dist/professional-management-platform/browser`

Render must keep the single-page application rewrite configured:

```text
/* -> /index.html
```

## Public build configuration

Configure these values in the Render static-site environment dashboard:

```text
RENDER_API_BASE_URL=https://api.your-domain.com
SUPPORT_EMAIL=support@your-domain.com
GOOGLE_OAUTH_CLIENT_ID=<google-oauth-web-client-id>.apps.googleusercontent.com
```

These values are public by design because they are included in the browser
bundle. Never put a Google client secret, SMTP password, database credential,
AWS secret, payment secret, private key, or access token in Render's frontend
environment.

`npm run build:render` writes these public values into
`frontend/public/app-config.js` immediately before the Angular production
build. The committed file intentionally contains blank values.

The Google OAuth Web Client ID must be identical to the backend
`GOOGLE_OAUTH_CLIENT_ID` and the Flutter `GOOGLE_SERVER_CLIENT_ID` build value.
A mismatch causes Google identity-token audience validation to fail.

## Test deployment workflow

1. Promote the approved release commit to the `Test` branch.
2. Allow Render to build that exact commit.
3. Confirm the Render build command and publish directory shown above.
4. Verify the RepRoot homepage, portal, professional login,
   client login, and protected-route behavior.
5. Confirm browser API requests use the HTTPS API URL and do not contain a
   duplicated `/api/accounts` path.
6. Keep the previous successful Render deploy available for rollback.

Changing a Render environment value requires a new static-site deployment so
the build script can place the new public value into the generated bundle.
