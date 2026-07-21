# How to View the Mobile App (Beginner Guide)

The mobile client is a native Flutter app (`mobile_flutter/`) — there is no browser
preview option; it always runs on an emulator or a real Android device.
**The backend never changes: it is always Django on port 8000.**

## Your ports (fixed)

| Thing | Where | When it runs |
| --- | --- | --- |
| Web frontend | `http://localhost:4300` | `cd frontend && npm start` |
| Backend API | `http://localhost:8000` | `cd backend && .venv\Scripts\python manage.py runserver 127.0.0.1:8000` |

The Flutter app talks to whichever `API_BASE_URL` you pass at launch — it isn't a
website, so there's no dev port for it the way the web frontend has one.

---

## Option A — Android emulator (fastest way to see the real app)

**One-time setup (~30-60 min, mostly downloads), if you don't already have one:**
1. Install **Android Studio**: https://developer.android.com/studio — accept the
   defaults (it installs the Android SDK for you).
2. Open Android Studio → **More Actions → Virtual Device Manager** → **Create Device**
   → pick "Pixel 7" → pick the newest system image (download it) → Finish.

**Every time:**
1. Start Django: `cd backend && .venv\Scripts\python manage.py runserver 127.0.0.1:8000`
2. Start the emulator: `scripts\start-flutter-emulator.ps1` (or open it from Android
   Studio's Device Manager)
3. Run the app, pointed at your PC through the emulator's special address:
   ```
   cd mobile_flutter
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
   ```
   Why `10.0.2.2`? Inside the emulator, "localhost" means the *virtual phone itself*;
   `10.0.2.2` is the emulator's alias for **your PC**, where Django is listening.

The Flutter SDK lives at `C:\flutter` — make sure `C:\flutter\bin` is on your `PATH`
(`$env:PATH = "C:\flutter\bin;$env:PATH"` in the same terminal if it isn't already).

After code changes, `flutter run` hot-reloads automatically while it's running —
press `r` in that terminal for a manual hot reload, or `R` for a full hot restart.

---

## Option B — Your own Android phone

1. On the phone: Settings → About phone → tap **Build number 7 times** (enables
   Developer mode) → Settings → Developer options → turn on **USB debugging**.
2. Plug the phone into your PC with a USB cable → allow the prompt on the phone.
3. Phone and PC must be on the **same Wi-Fi**. Find your PC's IP: run `ipconfig` →
   note the IPv4 address (e.g. `192.168.1.5`).
4. Start Django listening on the network, not just localhost:
   ```
   python manage.py runserver 0.0.0.0:8000
   ```
   and make sure that IP is in `DJANGO_ALLOWED_HOSTS` (check `backend/.env` /
   `config/settings.py`).
5. Run Flutter pointed at your PC's real LAN IP instead of the emulator alias:
   ```
   cd mobile_flutter
   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
   ```
   `flutter devices` will list your phone once it's plugged in and trusted; `flutter
   run` picks it automatically if it's the only device connected.

---

## Building a release APK

```
cd mobile_flutter
flutter build apk --release --dart-define=API_BASE_URL=https://your-production-domain
```

Release builds refuse a plaintext (`http://`) `API_BASE_URL` on purpose — see
`FLUTTER_PARITY_REPORT.md` for why, and the `ALLOW_INSECURE_API=true` escape hatch for
testing a release build against a LAN dev backend.

## What about iOS?

**Honest answer: you cannot build or test the iOS app on Windows.** Apple only allows
iOS builds through Xcode, which runs only on a Mac. No Android-only APIs sit outside
the platform folders, so the port should be mostly mechanical — but it has never
actually been compiled for iOS, so treat that as unverified until it happens.

## Common problems

| Symptom | Fix |
| --- | --- |
| Login fails on the emulator | `API_BASE_URL` must be `http://10.0.2.2:8000`, and Django must be running |
| Release build refuses to start | It rejected a plaintext `API_BASE_URL` — see the release-signing note above |
| "Lost connection to device" mid-session | The Flutter tooling process was killed; just re-run `flutter run` |
| Phone/emulator can't reach backend | Same Wi-Fi (for a real phone)? Windows Firewall may block port 8000 — allow Python when prompted |
