# CoachFlow Mobile (Ionic + Capacitor)

One app, two experiences: Trainer workspace and Client portal, role-chosen at launch.
Full design blueprint: `../Documentation/MOBILE_APP_DESIGN.md`.

## Quick start

```bash
npm install
npm start        # http://localhost:4400 (browser dev)
```

Set your backend URL in `src/environments/environment.ts` first:
- Browser dev: `http://127.0.0.1:8000`
- Android emulator: `http://10.0.2.2:8000`
- Real device: `http://<your-PC-LAN-IP>:8000`

## Native builds (needs Android Studio / Xcode)

```bash
npm run build
npx cap add android
npx cap add ios
npx cap sync
npx cap open android
```
