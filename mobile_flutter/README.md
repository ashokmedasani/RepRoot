# RepRoot Studio Flutter application

Flutter configuration is supplied at build time with `--dart-define`. These
values are public application configuration; no backend secret may be supplied
to an APK, app bundle, source file, asset, or Dart define.

## Configuration contract

| Variable | Purpose | Release requirement |
| --- | --- | --- |
| `API_BASE_URL` | Django API origin, without `/api/accounts` | HTTPS |
| `WEB_APP_URL` | Public RepRoot website used for legal documents | HTTPS |
| `STUDIO_WEB_URL` | RepRoot Studio website used for browser hand-offs | HTTPS |
| `GOOGLE_SERVER_CLIENT_ID` | Public Google OAuth Web Client ID | Same ID as backend and Angular |

The application appends `/api/accounts` itself. For example, supply
`https://api.your-domain.com`, not
`https://api.your-domain.com/api/accounts`.

## Local Android emulator

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=WEB_APP_URL=http://10.0.2.2:4300 --dart-define=STUDIO_WEB_URL=http://10.0.2.2:4300 --dart-define=GOOGLE_SERVER_CLIENT_ID=<google-oauth-web-client-id>.apps.googleusercontent.com
```

## Release app bundle

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.your-domain.com --dart-define=WEB_APP_URL=https://www.your-domain.com --dart-define=STUDIO_WEB_URL=https://studio.your-domain.com --dart-define=GOOGLE_SERVER_CLIENT_ID=<google-oauth-web-client-id>.apps.googleusercontent.com
```

Release builds reject a plaintext `API_BASE_URL`. Do not use
`ALLOW_INSECURE_API` for a distributed testing or production build.

The Google OAuth Web Client ID is intentionally public. Its corresponding
client secret, if one exists, belongs only in the backend secret store and must
never be included in Flutter.
