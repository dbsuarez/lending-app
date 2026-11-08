// Check, rehearse, or perform a restore of a Lending Manager backup.
//
//   node tool/backup/restore.mjs BACKUP.zip
//       Check only: checksums, references, balances. Changes nothing.
//   node tool/backup/restore.mjs BACKUP.zip --drill
//       Restore into a throw-away local database and compare. Changes nothing.
//   node tool/backup/restore.mjs BACKUP.zip --target-env TARGET_DB_URL [--ca CERT.crt] --yes
//       Restore into a NEW Supabase project (see docs/BACKUP_AND_RESTORE.md).
//       Refuses the production project and any project that already has data.
//       Optional: --storage-url https://NEW.supabase.co --service-key-env NEW_SERVICE_KEY
//       to upload the backed-up files too.
//       Optional: --map-user OLD_ID=NEW_ID (repeatable) for staff accounts.
import fs from 'node:fs';
import { readArchive } from './lib/archive.mjs';
import { restoreInto } from './lib/restore.mjs';
import { localDb } from './lib/localdb.mjs';
import { PRODUCTION_REF } from './lib/config.mjs';

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const file = args[0];
if (!file || file.startsWith('--')) {
  console.log('Usage: node tool/backup/restore.mjs BACKUP.zip [--drill | --target-env VAR --yes]');
  process.exit(2);
}

const backup = readArchive(new Uint8Array(fs.readFileSync(file)));
const m = backup.manifest;
if (m) {
  const rows = Object.values(m.tables ?? {}).reduce((s, t) => s + t.count, 0);
  console.log(`Backup of "${m.organization_name}" made ${m.exported_at} (${m.source}, schema ${m.schema_version ?? 'unknown'})`);
  console.log(`  ${rows} records, ${m.files?.length ?? 0} files${m.files_included ? '' : ' (files not included)'}, ` +
    `${m.totals?.loans ?? '?'} loans, active outstanding PHP ${((m.totals?.outstanding_active_centavos ?? 0) / 100).toLocaleString('en-PH', { minimumFractionDigits: 2 })}`);
}
if (!backup.ok) {
  console.log('CHECK FAILED:');
  for (const p of backup.problems) console.log('  - ' + p);
  process.exit(1);
}
console.log('Check passed: every checksum, reference and loan balance matches.');

const userMap = {};
args.forEach((a, i) => {
  if (a === '--map-user') {
    const [from, to] = (args[i + 1] ?? '').split('=');
    if (!from || !to) { console.log('--map-user needs OLD_ID=NEW_ID'); process.exit(2); }
    userMap[from] = to;
  }
});

function printReport(report) {
  for (const [t, n] of Object.entries(report.counts)) console.log(`  ${t.padEnd(22)} ${n}`);
  if (Object.keys(report.userMap ?? {}).length) {
    console.log('  user accounts moved: ' + Object.entries(report.userMap).map(([a, b]) => `${a} -> ${b}`).join(', '));
  }
  if (!report.ok) {
    console.log('RESTORE DOES NOT MATCH THE BACKUP:');
    for (const p of report.problems) console.log('  - ' + p);
    process.exit(1);
  }
}

if (args.includes('--drill')) {
  const report = await restoreInto(await localDb(), backup, { userMap });
  console.log('Restore drill (throw-away local database):');
  printReport(report);
  console.log('Drill passed: counts, every row and every loan balance match the backup.');
  process.exit(0);
}

const targetEnv = opt('--target-env');
if (!targetEnv) process.exit(0); // check only

const url = process.env[targetEnv];
if (!url) { console.log(`Environment variable ${targetEnv} is not set.`); process.exit(2); }
if (url.includes(PRODUCTION_REF)) {
  console.log('Refusing: that is the live production project. Restore only into a new, empty project.');
  process.exit(2);
}
if (!args.includes('--yes')) {
  console.log('Add --yes to write into the target project.');
  process.exit(2);
}

const { default: pg } = await import('pg');
const ca = opt('--ca');
const db = new pg.Client({
  connectionString: url.replace(/[?&]sslmode=[^&]*/, ''),
  // Always verify the server certificate. Supabase's CA certificate is on the
  // project's Database settings page; pass it with --ca.
  ssl: ca ? { ca: fs.readFileSync(ca, 'utf8'), rejectUnauthorized: true } : { rejectUnauthorized: true },
});
await db.connect();
try {
  const report = await restoreInto(db, backup, { userMap });
  console.log('Restored into the target project:');
  printReport(report);
} finally {
  await db.end();
}

const storageUrl = opt('--storage-url');
const keyEnv = opt('--service-key-env');
if (backup.files.length && storageUrl && keyEnv && process.env[keyEnv]) {
  if (storageUrl.includes(PRODUCTION_REF)) { console.log('Refusing to upload files to production.'); process.exit(2); }
  let n = 0;
  const mime = new Map(backup.tables.loan_documents.map((d) => [d.storage_path, d.mime_type]));
  for (const f of backup.files) {
    const r = await fetch(`${storageUrl.replace(/\/$/, '')}/storage/v1/object/${f.bucket}/${f.path.split('/').map(encodeURIComponent).join('/')}`, {
      method: 'POST',
      headers: { authorization: `Bearer ${process.env[keyEnv]}`, 'x-upsert': 'true', 'content-type': mime.get(f.path) ?? 'application/octet-stream' },
      body: f.bytes,
    });
    if (!r.ok) { console.log(`File upload failed for ${f.path}: HTTP ${r.status}`); process.exit(1); }
    n++;
  }
  console.log(`Uploaded ${n} files.`);
} else if (backup.files.length) {
  console.log(`Note: ${backup.files.length} files were not uploaded (pass --storage-url and --service-key-env).`);
}
console.log('Restore complete and verified.');
