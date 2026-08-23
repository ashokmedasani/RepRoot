/**
 * Verifies every element the guided tour points at still exists in a template.
 *
 * The tour targets `data-tour="..."` attributes. Rename or delete one and the
 * tour silently skips that step — the build succeeds, the unit tests pass, and
 * nobody finds out until a professional watches the tour jump over something.
 * This is the only check that catches it, so it runs as part of `npm test`.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'app');

function walk(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

const files = walk(root);
const markup = files
  .filter((f) => f.endsWith('.html') || f.endsWith('.ts'))
  .map((f) => readFileSync(f, 'utf8'))
  .join('\n');

const guide = readFileSync(join(root, 'core', 'guide', 'guide.service.ts'), 'utf8');
const targets = [...guide.matchAll(/data-tour="([a-z-]+)"/g)].map((m) => m[1]);
const declared = [...new Set(targets)];

const missing = declared.filter(
  (name) => !new RegExp(`data-tour="${name}"`).test(markup.replace(guide, ''))
);

if (missing.length) {
  console.error('Guide tour targets with no matching element in any template:');
  for (const name of missing) {
    console.error(`  - data-tour="${name}"`);
  }
  process.exit(1);
}

// The overlay must be mounted at the application root. Anywhere inside a
// routed component it is destroyed and rebuilt on every navigation, which
// kills the running step's poll timer and router subscription mid-tour.
const hosts = files
  .filter((f) => f.endsWith('.html'))
  .filter((f) => /<app-guide-overlay\s*\/?>/.test(readFileSync(f, 'utf8')));
const strayHosts = hosts.filter((f) => !f.endsWith('app.component.html'));

if (strayHosts.length) {
  console.error('<app-guide-overlay /> must only be mounted in app.component.html. Found in:');
  for (const f of strayHosts) console.error(`  - ${f}`);
  process.exit(1);
}

console.log(`guide anchors OK: ${declared.length} tour targets all resolve.`);
