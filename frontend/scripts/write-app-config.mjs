import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const frontendDir = join(__dirname, '..');
const publicDir = join(frontendDir, 'public');
const configPath = join(publicDir, 'app-config.js');

/**
 * Reads `backend/.env` as a fallback source for local development.
 *
 * Why this exists: these values live in `backend/.env`, which is loaded by
 * Django — not by Node. `process.env` in an `npm` script only sees the shell
 * environment, so locally every value came out empty and `app-config.js` was
 * written blank. A blank `googleClientId` makes the Google sign-in button
 * render nothing at all (no button, no error), which reads as a broken app
 * rather than as missing configuration.
 *
 * Deployment is unaffected: real environment variables always win, and this
 * file does not exist in a deployed build.
 */
function readBackendEnv() {
  const envPath = join(frontendDir, '..', 'backend', '.env');
  if (!existsSync(envPath)) {
    return {};
  }

  const values = {};
  for (const rawLine of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    const separator = line.indexOf('=');
    if (separator === -1) {
      continue;
    }
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    // Strip one layer of matching quotes, the way dotenv does.
    if (value.length > 1 && ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

const fileEnv = readBackendEnv();

/** Real environment first, then backend/.env, then the default. */
const pick = (keys, fallback = '') => {
  for (const key of keys) {
    const fromProcess = process.env[key];
    if (fromProcess && fromProcess.trim()) {
      return fromProcess.trim();
    }
  }
  for (const key of keys) {
    const fromFile = fileEnv[key];
    if (fromFile && fromFile.trim()) {
      return fromFile.trim();
    }
  }
  return fallback;
};

const apiBaseUrl = pick(['RENDER_API_BASE_URL', 'API_BASE_URL']);
const supportEmail = pick(['SUPPORT_EMAIL']);
// Public OAuth Web Client ID (not a secret) for the "Continue with Google" /
// "Log in with Google" buttons. The buttons do not render when this is blank.
const googleClientId = pick(['GOOGLE_OAUTH_CLIENT_ID']);

const contents = `window.APP_CONFIG = {\n  apiBaseUrl: ${JSON.stringify(apiBaseUrl)},\n  supportEmail: ${JSON.stringify(supportEmail)},\n  googleClientId: ${JSON.stringify(googleClientId)}\n};\n`;

mkdirSync(publicDir, { recursive: true });

/**
 * Writing this file must never be able to fail the build.
 *
 * On Windows this file sits inside a watched folder; a running `ng serve`,
 * OneDrive sync, or an antivirus scanner can hold a handle on it, and Node then
 * throws `UNKNOWN: unknown error, open ...`. Because this script is chained
 * ahead of `ng build` with `&&`, that crash killed the build before the Angular
 * compiler ever started — with an error that says nothing about Angular.
 *
 * So: skip the write when the contents are already correct (the common case),
 * write through a temp file and rename when they are not, and if even that
 * fails, warn and carry on with whatever is already on disk.
 */
let alreadyCorrect = false;
try {
  alreadyCorrect = existsSync(configPath) && readFileSync(configPath, 'utf8') === contents;
} catch {
  alreadyCorrect = false;
}

if (!alreadyCorrect) {
  try {
    const tempPath = `${configPath}.tmp`;
    writeFileSync(tempPath, contents, 'utf8');
    renameSync(tempPath, configPath);
  } catch (error) {
    console.warn(`app-config.js could not be rewritten (${error.code || error.message}).`);
    console.warn('Keeping the existing file and continuing the build.');
    if (!existsSync(configPath)) {
      console.warn('There is no existing app-config.js — the app will use its built-in defaults.');
    }
  }
}

// Say what landed. A silent script that writes empty strings is exactly how
// the blank-config problem stayed invisible.
const describe = (label, value, note = '') =>
  `  ${label.padEnd(16)}${value ? 'set' : 'EMPTY'}${note && !value ? ` — ${note}` : ''}`;

console.log('app-config.js written:');
console.log(describe('apiBaseUrl', apiBaseUrl, 'frontend will fall back to localhost:8000'));
console.log(describe('supportEmail', supportEmail));
console.log(describe('googleClientId', googleClientId, 'the Google sign-in button will NOT render'));
