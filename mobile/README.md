# CoachFlow Android (Ionic + Capacitor)

One Android app with two experiences: Trainer workspace and Client portal, role-chosen at launch.
Full design blueprint: `../Documentation/MOBILE_APP_DESIGN.md`.

Implemented trainer areas: Dashboard, Clients, Client Detail (notes, schedules,
progress history, and shared details), Forms & Groups, Templates, Profile,
References, Settings, percentage-only storage usage, structured support requests,
and logout.

Implemented client areas: Dashboard KPIs, Programs/templates and entry
submission, Progress charts from real numeric/rating entries, Trainer Profile,
Chat, Settings, password change, legal information, structured bug/feedback
requests, account deletion request/withdrawal, and logout.

## Quick start

```bash
npm install
npm start        # http://localhost:4400 (browser dev)
```

Set your backend URL in `src/environments/environment.ts` first:
- Browser dev: `http://127.0.0.1:8000`
- Android emulator: `http://10.0.2.2:8000`
- Real device: `http://<your-PC-LAN-IP>:8000`

## Android build (needs Android Studio)

```bash
npm run build
npm run android:sync
npm run android:open
```

The Android project lives in `android/`. No iOS platform is included. For a
physical device, keep the phone and backend PC on the same Wi-Fi and update
`src/environments/environment.ts` if the PC IPv4 address changes.

The debug APK is produced at
`android/app/build/outputs/apk/debug/app-debug.apk`. Android builds require
Android Studio's bundled JDK 17/21 and an installed Android SDK. The project
uses `android/local.properties` for the local SDK path; do not commit that
machine-specific file.
