// Rehearses per-loan restore on real backups, locally:
//   node tool/backup/restore_loan_real_check.mjs LIVE.zip BACKUP.zip [loanId ...]
// Loads LIVE into a throw-away database, checks that previewing every loan
// against its own data changes nothing, then restores the given loans (or
// every changed loan) from BACKUP and compares them with BACKUP.
import fs from 'node:fs';
import { readArchive, loanStateFromTables, remapUsers, TABLES } from './lib/archive.mjs';
import { restoreInto } from './lib/restore.mjs';
import { localDb } from './lib/localdb.mjs';

const [liveFile, backupFile, ...only] = process.argv.slice(2);
const live = readArchive(new Uint8Array(fs.readFileSync(liveFile)));
const backup = readArchive(new Uint8Array(fs.readFileSync(backupFile)));
const db = await localDb();
const loaded = await restoreInto(db, live);
const map = loaded.userMap;
const owner = Object.values(map)[0];
await db.query(`select set_config('test.uid',$1,false)`, [owner]);
const canon = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort()) : x));
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };

// 1. A loan restored to its own current data: preview shows no change.
const liveTables = remapUsers(live.tables, map);
let same = 0;
for (const l of liveTables.loans) {
  const p = (await db.query(`select public.loan_restore_preview($1,$2::jsonb) j`, [l.id, JSON.stringify(loanStateFromTables(liveTables, l.id))])).rows[0].j;
  if (canon(p.now) === canon(p.after)) same++; else console.log('  differs:', l.id.slice(0, 8));
}
ok(`preview with a loan's own data changes nothing (${same}/${liveTables.loans.length} loans)`, same === liveTables.loans.length);

// 2. Restore loans from the older backup.
const backupTables = remapUsers(backup.tables, map);
const ids = only.length ? only : [...new Set([...backupTables.loans, ...liveTables.loans].map((l) => l.id))];
let restored = 0;
for (const id of ids) {
  const state = loanStateFromTables(backupTables, id);
  const p = (await db.query(`select public.loan_restore_preview($1,$2::jsonb) j`, [id, JSON.stringify(state)])).rows[0].j;
  if (canon(p.now) === canon(p.after)) continue;
  await db.query(`select public.restore_loan($1,$2::jsonb,'Rehearsal',now(),$3)`, [id, JSON.stringify(state), crypto.randomUUID()]);
  restored++;
  console.log('  restored', id.slice(0, 8), state ? '' : '(removed)');
}
// Every restored loan now equals the backup (compared through Postgres types).
let diffs = 0;
for (const id of ids) {
  const state = loanStateFromTables(backupTables, id);
  const want = state ? (await db.query(`select public.loan_restore_preview($1,$2::jsonb) j`, [id, JSON.stringify(state)])).rows[0].j : null;
  const nowState = (await db.query(`select public._loan_state($1) j`, [id])).rows[0].j;
  if (state === null ? nowState !== null : canon(want.after) !== canon(nowState)) { diffs++; console.log('  still differs', id.slice(0, 8)); }
}
ok(`${restored} loan(s) restored; all match the backup`, diffs === 0);
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
