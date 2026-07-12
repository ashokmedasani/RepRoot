# How to View Your Mobile App (Beginner Guide)

You have never built a mobile app before — that's fine. There are 3 ways to see it,
from easiest to most real. **The backend never changes: it is always Django on port 8000.**

## Your ports (fixed)

| Thing | Where | When it runs |
| --- | --- | --- |
| Web frontend | `http://localhost:4300` | `cd frontend && npm start` |
| Backend API | `http://localhost:8000` | `cd backend && .venv\Scripts\python manage.py runserver` |
| Mobile preview (browser) | `http://localhost:4400` | only while you run `cd mobile && npm start` — close it when done |

The old 4200 references were removed. The mobile app is NOT a website — 4400 is just a
developer preview; the real thing runs inside an emulator or a phone (below).

---

## Option A — Browser preview (5 minutes, do this first)

The mobile app is web technology inside a native shell, so Chrome can preview it.

1. Start the backend as usual (port 8000).
2. ```
   cd mobile
   npm start
   ```
3. Open `http://localhost:4400` in Chrome.
4. Press **F12** → click the **phone icon** (top-left of DevTools, or Ctrl+Shift+M).
   Chrome now shows the app in a phone-sized frame. Pick "iPhone 12" or "Pixel 7" from the dropdown.
5. Tap "I'm a Trainer" → log in with your normal trainer account → your real data appears.

That's your mobile app, pixel-for-pixel, minus the native shell.

---

## Option A+ — On your ACTUAL phone's browser over Wi-Fi (10 minutes, no installs)

Your PC's Wi-Fi address is **192.168.4.68**. One script starts everything:

```
powershell -ExecutionPolicy Bypass -File scripts\start-mobile-test.ps1
```

It opens two windows (backend + mobile server) and prints the URL. Then on your
phone (same Wi-Fi), open the browser and type:

```
http://192.168.4.68:4400
```

The app appears full-screen on your phone and talks to your real backend — the
API address is detected automatically, no editing needed. Tip: in Chrome on the
phone, menu → **"Add to Home screen"** puts a CoachFlow icon on your phone that
opens like an app.

If it doesn't load: the first time, Windows Firewall pops up asking to allow
Node and Python — click **Allow**. And confirm both devices are on the same Wi-Fi.

---

## Option B — Real Android emulator (the actual app on a virtual phone)

**One-time setup (~30-60 min, mostly downloads):**
1. Install **Android Studio**: https://developer.android.com/studio — run the installer,
   accept the defaults (it installs the Android SDK for you).
2. Open Android Studio → **More Actions → Virtual Device Manager** → **Create Device**
   → pick "Pixel 7" → pick the newest system image (click download next to it) → Finish.
   This creates your virtual phone.

**Point the app at your backend:**
3. Open `mobile/src/environments/environment.ts` and change the URL to:
   ```ts
   apiBaseUrl: 'http://10.0.2.2:8000'
   ```
   Why? Inside the emulator, "localhost" means the *virtual phone itself*.
   `10.0.2.2` is the emulator's special address for **your PC**, where Django runs.
   (The backend is already configured to accept this — nothing to change there.)

**Build and run (every time):**
4. ```
   cd mobile
   npm run build
   npx cap add android        # first time only - creates the android/ project
   npx cap sync               # copies your latest build into it
   npx cap open android       # opens Android Studio
   ```
5. In Android Studio: wait for the bottom progress bar to finish ("Gradle sync"),
   pick your Pixel 7 in the device dropdown (top toolbar), press the green **▶ Run** button.
6. The virtual phone boots and **CoachFlow installs and opens like a real app**.
   Make sure Django is running on your PC (`manage.py runserver`) — log in and use it.

After code changes: `npm run build && npx cap sync`, then press ▶ again.

---

## Option C — Your own Android phone

1. On the phone: Settings → About phone → tap **Build number 7 times** (enables Developer mode)
   → Settings → Developer options → turn on **USB debugging**.
2. Plug the phone into your PC with a USB cable → allow the prompt on the phone.
3. Phone and PC must be on the **same Wi-Fi**. Find your PC's IP: run `ipconfig`
   → note the IPv4 address (e.g. `192.168.1.5`).
4. In `mobile/src/environments/environment.ts`:
   ```ts
   apiBaseUrl: 'http://192.168.1.5:8000'    // your PC's IP
   ```
5. Two backend tweaks for this case only:
   - Start Django listening to the network: `python manage.py runserver 0.0.0.0:8000`
   - Set the env var before starting: `set DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,10.0.2.2,192.168.1.5`
6. `npm run build && npx cap sync && npx cap open android` → in Android Studio your
   real phone appears in the device dropdown → press ▶. The app installs on your phone.

---

## What about iOS?

**Honest answer: you cannot build or test the iOS app on Windows.** Apple only allows
iOS builds through Xcode, which runs only on a Mac. Your options later:
- Borrow/buy a Mac → `npx cap add ios && npx cap open ios` → run in the iPhone simulator.
- Use a cloud build service (Ionic Appflow, Codemagic) that builds iOS for you.
The codebase is already iOS-ready — nothing to rewrite when that day comes.

## Common problems

| Symptom | Fix |
| --- | --- |
| Login fails in emulator | environment.ts must be `http://10.0.2.2:8000`, and Django must be running |
| "Cleartext HTTP" error on Android | We use http in dev; if Android blocks it, add `android:usesCleartextTraffic="true"` to `android/app/src/main/AndroidManifest.xml` `<application>` tag |
| Blank screen after build | Run `npx cap sync` again — it copies the fresh build into the native project |
| Phone can't reach backend | Same Wi-Fi? Windows Firewall may block port 8000 — allow Python when prompted |
