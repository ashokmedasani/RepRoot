/**
 * API base URL.
 *
 * Browser / phone-over-Wi-Fi testing: derived automatically from wherever the
 * app is served. Open http://localhost:4400 -> API at http://localhost:8000;
 * open http://192.168.4.68:4400 from your phone -> API at
 * http://192.168.4.68:8000. No editing needed.
 *
 * NATIVE (installed) builds run from "localhost" inside the Capacitor shell,
 * so they fall back to NATIVE_API_URL below. Set it before building natively:
 *   - Android emulator:            'http://10.0.2.2:8000'
 *   - Installed on a real phone:   'http://192.168.4.68:8000' (your PC's IP)
 *   - Production:                  your deployed backend URL
 */
const NATIVE_API_URL = 'http://192.168.4.68:8000';

interface CapacitorGlobal {
  Capacitor?: { isNativePlatform?: () => boolean };
}

const capacitor = (globalThis as CapacitorGlobal).Capacitor;
const isNative = Boolean(capacitor?.isNativePlatform?.());
const hostname = typeof window !== 'undefined' && window.location.hostname ? window.location.hostname : 'localhost';

export const environment = {
  production: false,
  apiBaseUrl: isNative ? NATIVE_API_URL : `http://${hostname}:8000`
};
