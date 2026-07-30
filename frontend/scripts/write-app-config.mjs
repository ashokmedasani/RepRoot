import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = join(__dirname, '..', 'public');
const configPath = join(publicDir, 'app-config.js');
const apiBaseUrl = process.env.RENDER_API_BASE_URL || process.env.API_BASE_URL || '';
const supportEmail = process.env.SUPPORT_EMAIL || '';
// Public OAuth Web Client ID (not a secret) for the "Continue with Google" /
// "Log in with Google" buttons. Empty until a real Google Cloud OAuth client
// is created -- the buttons simply don't render when this is blank.
const googleClientId = process.env.GOOGLE_OAUTH_CLIENT_ID || '';

mkdirSync(publicDir, { recursive: true });
writeFileSync(
  configPath,
  `window.APP_CONFIG = {\n  apiBaseUrl: ${JSON.stringify(apiBaseUrl)},\n  supportEmail: ${JSON.stringify(supportEmail)},\n  googleClientId: ${JSON.stringify(googleClientId)}\n};\n`,
  'utf8',
);
