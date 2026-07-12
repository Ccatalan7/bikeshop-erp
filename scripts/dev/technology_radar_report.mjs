import fs from 'node:fs/promises';

const toolchain = JSON.parse(await fs.readFile(new URL('../../toolchain.json', import.meta.url)));

async function json(url) {
  const response = await fetch(url, {headers: {'user-agent': 'vinabike-tool-radar'}});
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}

async function npmLatest(packageName) {
  const metadata = await json(`https://registry.npmjs.org/${encodeURIComponent(packageName)}/latest`);
  return metadata.version;
}

const checks = [
  ['Node LTS line', toolchain.node, async () => {
    const releases = await json('https://nodejs.org/dist/index.json');
    return releases.find((release) => release.version.startsWith('v24.'))?.version.replace(/^v/, '') ?? 'unknown';
  }],
  ['Supabase CLI', toolchain.supabaseCli, () => npmLatest('supabase')],
  ['Firebase CLI', toolchain.firebaseCli, () => npmLatest('firebase-tools')],
  ['Playwright', toolchain.playwright, () => npmLatest('@playwright/test')],
  ['Wrangler', toolchain.wrangler, () => npmLatest('wrangler')],
];

const rows = [];
for (const [name, pinned, resolveLatest] of checks) {
  try {
    const latest = await resolveLatest();
    rows.push([name, pinned, latest, pinned === latest ? 'Current' : 'Review']);
  } catch (error) {
    rows.push([name, pinned, 'lookup failed', `Retry: ${error.message}`]);
  }
}

console.log('# Weekly Vinabike technology radar');
console.log('');
console.log(`Generated: ${new Date().toISOString()}`);
console.log('');
console.log('| Capability | Pinned | Available | Action |');
console.log('|---|---:|---:|---|');
for (const row of rows) console.log(`| ${row.join(' | ')} |`);
console.log('');
console.log('This report discovers candidates only. Adoption requires the risk-based proof and rollback defined in `docs/development/UPGRADE_POLICY.md`.');
