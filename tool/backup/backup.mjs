// Weekly backup: export everything (including uploaded files) as the owner,
// check the file, prove it restores on a throw-away local database, keep the
// newest N, and log the result. Exit code 0 only when all of that passed.
//
//   node tool/backup/backup.mjs [--out DIR] [--copy-to DIR] [--keep 12] [--no-files] [--no-drill]
import fs from 'node:fs';
import path from 'node:path';
import { buildArchive, readArchive } from './lib/archive.mjs';
import { signIn, api, exportOrganization } from './lib/export_rest.mjs';
import { restoreInto } from './lib/restore.mjs';
import { localDb, latestMigration } from './lib/localdb.mjs';
import { appConfig, ownerLogins, REPO } from './lib/config.mjs';

const args = process.argv.slice(2);
const opt = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const outDir = path.resolve(opt('--out', path.join(REPO, 'backups')));
const copyTo = opt('--copy-to', process.env.LM_BACKUP_COPY_TO);
const keep = Number(opt('--keep', 12));
const includeFiles = !args.includes('--no-files');
const drill = !args.includes('--no-drill');
const logFile = path.join(outDir, 'backup-log.txt');

fs.mkdirSync(outDir, { recursive: true });
const now = new Date();
const pad = (n) => String(n).padStart(2, '0');
const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}`;
const log = (msg) => { console.log(msg); fs.appendFileSync(logFile, `${new Date().toISOString()} ${msg}\n`); };

try {
  const cfg = appConfig();
  let session = null;
  for (const login of ownerLogins()) {
    session = await signIn({ ...cfg, ...login });
    if (session) break;
  }
  if (!session) throw new Error('Could not sign in as the owner (check .env DEV_LOGIN_* or docs/notes_la).');
  const client = api({ ...cfg, token: session.token });

  const exported = await exportOrganization(client, session.userId, { includeFiles });
  const { bytes, manifest } = buildArchive({ source: 'weekly-backup', schemaVersion: latestMigration(), ...exported });
  const backup = readArchive(bytes);
  if (!backup.ok) throw new Error(`Backup failed its own check: ${backup.problems.slice(0, 5).join('; ')}`);

  const file = path.join(outDir, `lending-manager-backup-${stamp}.zip`);
  fs.writeFileSync(file, bytes);
  const rows = Object.values(manifest.tables).reduce((s, t) => s + t.count, 0);
  let summary = `${path.basename(file)}: ${rows} records, ${manifest.files.length} files, ${(bytes.length / 1048576).toFixed(1)} MB`;

  if (drill) {
    const report = await restoreInto(await localDb(), backup);
    if (!report.ok) throw new Error(`Restore drill FAILED for ${path.basename(file)}: ${report.problems.slice(0, 5).join('; ')}`);
    summary += '; restore drill passed (counts, every row, balances)';
  }

  if (copyTo) {
    fs.mkdirSync(copyTo, { recursive: true });
    fs.copyFileSync(file, path.join(copyTo, path.basename(file)));
    summary += `; copied to ${copyTo}`;
  }

  // Keep the newest N backups in each folder.
  for (const dir of [outDir, copyTo].filter(Boolean)) {
    const old = fs.readdirSync(dir).filter((f) => /^lending-manager-backup-.*\.zip$/.test(f)).sort().reverse().slice(keep);
    for (const f of old) fs.rmSync(path.join(dir, f));
  }

  // Leave a record in the app's history that a checked backup exists.
  try {
    await client.rpc('record_backup_verification', { p_exported_at: manifest.exported_at, p_record_count: rows });
  } catch (e) {
    summary += `; (history note not saved: ${e.message.slice(0, 80)})`;
  }
  log(`OK ${summary}`);
} catch (e) {
  log(`FAILED ${e.message}`);
  process.exit(1);
}
