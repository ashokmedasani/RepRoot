# "Continue with Google" Production Setup

RepRoot professionals can sign up or log in with a Google account instead of
an email/password. This is separate from the Google Calendar/Meet
integration (see `GOOGLE_CALENDAR_MEET_SETUP.md`) -- it uses its own,
different Google Cloud OAuth client, and is disabled everywhere (no button
renders, no error is shown) until it is configured.

Real credentials are user-managed. Agents must never open or edit the real
environment file.

## 1. Create the Google OAuth Web Client

1. Open Google Cloud Console and create or select the production project
   (the same project used for Google Calendar/Meet is fine, or a separate one
   -- either works).
2. Configure the OAuth consent screen if it isn't already set up.
3. Create an **OAuth 2.0 Client ID**.
4. Select **Web application**.
5. Under **Authorized JavaScript origins**, add every origin the sign-in
   button will actually be loaded from:
   - `https://rep-root.com` (production)
   - `https://www.rep-root.com` (if used)
   - `http://localhost:4300` (local frontend dev server)
6. This flow uses Google Identity Services' popup/One Tap credential
   callback, not a server-side redirect, so **no Authorized redirect URI**
   is required.
7. Copy the generated **Client ID**. It is public by design (it gets shipped
   in frontend JavaScript) -- do not confuse it with a client secret; nothing
   here needs one.

## 2. Add the environment value

Backend (verifies the Google ID token on every sign-in):

```env
GOOGLE_OAUTH_CLIENT_ID=<google-oauth-web-client-id>
```

Frontend (embeds the same Client ID in the built JavaScript bundle at build
time via `frontend/scripts/write-app-config.mjs` -> `public/app-config.js`):

```env
GOOGLE_OAUTH_CLIENT_ID=<google-oauth-web-client-id>
```

On Render, this is the `GOOGLE_OAUTH_CLIENT_ID` entry already present (as
`sync: false`) in `render.yaml`'s `reproot-web` service -- fill it in from the
Render dashboard rather than committing the value. Add the same variable to
the backend host's environment configuration.

| Variable | Secret | Source |
| --- | --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Treat as private, but not a secret | Google Cloud OAuth client (Web application) |

Restart or redeploy both the frontend and backend after adding it.

## 3. Apply the database migration

```text
python manage.py migrate
```

Adds `google_sub` / `google_linked_at` to `ProfessionalProfile` so a Google
account can be linked to a professional's account.

## 4. Behavior once configured

- The signup and login pages both render Google's own button
  ("Sign up with Google" / "Log in with Google").
- New Google sign-in with no matching account: creates a professional
  account, marks the email verified (Google already verified it, so no OTP
  step), generates a unique username from the email, and redirects straight
  to mandatory Profile Setup.
- Google sign-in with an email that matches an existing password-based
  professional account: links the Google account to the existing one (no
  duplicate account) and logs the user in.
- Returning Google user: logs in and redirects to the dashboard if profile
  setup is complete, or Profile Setup if not.
- Token verification happens entirely on the backend
  (`accounts/google_oauth.py`); the frontend never decides who is logged in
  based on the Google response alone.

## 5. Until this is configured

The Google button simply does not render (checked via
`APP_CONFIG.googleClientId` on the frontend and `GOOGLE_OAUTH_ENABLED` on the
backend). Email/password signup and login are unaffected either way.
