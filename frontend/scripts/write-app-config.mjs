import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = join(__dirname, '..', 'public');
const configPath = join(publicDir, 'app-config.js');
const apiBaseUrl = process.env.RENDER_API_BASE_URL || process.env.API_BASE_URL || '';

mkdirSync(publicDir, { recursive: true });
writeFileSync(
  configPath,
  `window.APP_CONFIG = {\n  apiBaseUrl: ${JSON.stringify(apiBaseUrl)}\n};\n`,
  'utf8',
);
