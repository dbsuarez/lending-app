// Per-loan restore (migration 202611090037) on a local database:
// replays the "test changes on a real loan" situation and restores it.
// Run: node tool/backup/restore_loan_test.mjs
import { TABLES, orgColumnOf, computeBalances, loanStateFromTables } from './lib/archive.mjs';
import { localDb, OWNER_EMAIL } from './lib/localdb.mjs';

const A = '00000000-0000-0000-0000-00000000000a'; // owner
const B = '00000000-0000-0000-0000-00000000000b'; // manager
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };
const uuid = () => crypto.randomUUID();

const db = await localDb({ users: [{ id: A, email: OWNER_EMAIL }, { id: B, email: 'manager@example.test' }] });
const val = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0] ?? {})[0];
const as = (uid) => db.query(`select set_config('test.uid',$1,false)`, [uid]);
const refuses = async (name, sql, params, pattern) => {
  try { await db.query(sql, params); ok(`${name} (should refuse)`, false); }
  catch (e) { ok(`${name} -> "${e.message}"`, pattern.test(e.message), e.message); }
};
function schedule(principal, rateBp, term, day1 = 15, day2 = 28) {
  const interest = Math.round(principal * rateBp * term / 10000), total = principal + interest;
  const n = term * 2, base = Math.floor(total / n), baseP = Math.floor(principal / n);
  let used = 0, usedP = 0; const out = [];
  for (let i = 0; i < n; i++) {
    const amt = i === n - 1 ? total - used : base, p = i === n - 1 ? principal - usedP : baseP;
    const m = 9 + Math.floor(i / 2);
    out.push({ sequence: i + 1, due_date: `2026-${String(m).padStart(2, '0')}-${i % 2 ? day2 : day1}`,
      principal_centavos: p, interest_centavos: amt - p, scheduled_centavos: amt });
    used += amt; usedP += p;
  }
  return out;
}
async function dump() {
  const tables = {};
  for (const t of TABLES) {
    tables[t] = (await db.query(`select coalesce(jsonb_agg(to_jsonb(x) order by x::text),'[]'::jsonb) j from public.${t} x`)).rows[0].j;
  }
  return tables;
}

const org = await val(`select organization_id from public.organization_members where user_id=$1`, [A]);
await db.query(`insert into public.organization_members(organization_id,user_id,role,status) values($1,$2,'manager','active')`, [org, B]);
await as(A);
const bor = await val(`select public.save_borrower(null,'Mayshell','Test','0917',null,'Manila')`);
const L1 = await val(`select public.create_loan_draft($1,$2,1000000,600,2,'2026-09-15','{15,28}',$3::jsonb,$4)`, [org, bor, JSON.stringify(schedule(1000000, 600, 2)), uuid()]);
const L2 = await val(`select public.create_loan_draft($1,$2,1500000,500,1,'2026-09-20','{5,20}',$3::jsonb,$4)`, [org, bor, JSON.stringify(schedule(1500000, 500, 1, 20, 5).map((x, i) => ({ ...x, due_date: i ? '2026-10-05' : '2026-09-20' }))), uuid()]);
await db.query(`select public.activate_loan($1,'2026-09-01','GCash','R1',$2)`, [L1, uuid()]);
await db.query(`select public.activate_loan($1,'2026-09-01','Legacy import','Imported',$2)`, [L2, uuid()]);
const p1 = await val(`select public.record_pending_payment($1,280000,'2026-09-15 10:00+08','GCash','',$2,'test')`, [L1, uuid()]);
await db.query(`select public.verify_payment($1)`, [p1]);
await db.query(`select public.register_loan_document($1,'payment_evidence',$2,'r.jpg','image/jpeg',5)`, [L1, `${org}/${L1}/r.jpg`]);

// ---- The backup ---------------------------------------------------------------
const backup = await dump();
const backupBalances = computeBalances(backup);

// ---- Mistakes after the backup ------------------------------------------------
await db.query(`select public.correct_loan($1,$2,1500000,500,1,'2026-09-15','{15,30}',$3::jsonb,'2026-09-01','MariBank','R9','Correcting something',$4)`,
  [L2, bor, JSON.stringify(schedule(1500000, 500, 1, 15, 30).map((x, i) => ({ ...x, due_date: i ? '2026-09-30' : '2026-09-15' }))), uuid()]);
const D = await val(`select public.refinance_loan($1,1500000,500,1,$2::jsonb,'Adjusting the date','2026-11-06',null,$3)`,
  [L2, JSON.stringify(schedule(1500000, 500, 1)), uuid()]);
await db.query(`select public.cancel_loan_draft($1,'Doing this wrong')`, [D]);
await db.query(`select public.reverse_payment($1,'Oops')`, [p1]);
await db.query(`select public.record_collection_activity($1,'call','promised','Test note','2026-10-02',1000,$2)`, [L1, uuid()]);

// ---- Preview --------------------------------------------------------------------
const stateL2 = loanStateFromTables(backup, L2);
const preview = await val(`select public.loan_restore_preview($1,$2::jsonb)`, [L2, JSON.stringify(stateL2)]);
ok('preview: now refinanced, after active', preview.now.loan.status === 'refinanced' && preview.after.loan.status === 'active');
ok('preview: after has the backup schedule', JSON.stringify(preview.after.installments.map((i) => i.id).sort()) === JSON.stringify(stateL2.installments.map((i) => i.id).sort()));
ok('preview changes nothing', (await val(`select status::text from public.loans where id=$1`, [L2])) === 'refinanced');
ok('preview of a loan not in the backup: after = removed', (await val(`select public.loan_restore_preview($1,null)`, [D])).after === null);

// ---- Who may restore --------------------------------------------------------------
await as(B);
await refuses('manager cannot restore', `select public.restore_loan($1,$2::jsonb,'Fix test',now(),$3)`, [L2, JSON.stringify(stateL2), uuid()], /Only the owner/);
await as(A);
await refuses('reason required', `select public.restore_loan($1,$2::jsonb,'',now(),$3)`, [L2, JSON.stringify(stateL2), uuid()], /reason/);
const bad = structuredClone(stateL2); bad.installments[0].loan_id = L1;
await refuses('records of another loan refused', `select public.restore_loan($1,$2::jsonb,'Fix test',now(),$3)`, [L2, JSON.stringify(bad), uuid()], /another loan/);

// ---- Restore --------------------------------------------------------------------
const op = uuid();
const r2 = await val(`select public.restore_loan($1,$2::jsonb,'Undo my tests',now(),$3)`, [L2, JSON.stringify(stateL2), op]);
ok('same request twice returns the same restore', (await val(`select public.restore_loan($1,$2::jsonb,'Undo my tests',now(),$3)`, [L2, JSON.stringify(stateL2), op])) === r2);
const rD = await val(`select public.restore_loan($1,null,'Remove test draft',now(),$2)`, [D, uuid()]);
ok('draft made after the backup is removed', (await val(`select count(*)::int from public.loans where id=$1`, [D])) === 0);
const r1 = await val(`select public.restore_loan($1,$2::jsonb,'Undo reversal',now(),$3)`, [L1, JSON.stringify(loanStateFromTables(backup, L1)), uuid()]);
await refuses('restoring again: nothing to do', `select public.restore_loan($1,$2::jsonb,'Again',now(),$3)`, [L1, JSON.stringify(loanStateFromTables(backup, L1)), uuid()], /already matches/);

// The whole database equals the backup again, except history and the restore log.
const now = await dump();
let diffs = [];
for (const t of TABLES.filter((t) => t !== 'audit_events')) {
  const key = (r) => (t === 'organization_members' ? r.organization_id + r.user_id : r.id);
  const a = new Map(backup[t].map((r) => [key(r), JSON.stringify(r)]));
  const b = new Map(now[t].map((r) => [key(r), JSON.stringify(r)]));
  for (const k of new Set([...a.keys(), ...b.keys()])) if (a.get(k) !== b.get(k)) diffs.push(`${t}:${k.slice(0, 8)}`);
}
ok('every table equals the backup again', diffs.length === 0, diffs.join(' '));
ok('balances equal the backup', JSON.stringify(computeBalances(now)) === JSON.stringify(backupBalances));
ok('evidence kept', (await val(`select count(*)::int from public.loan_documents where loan_id=$1`, [L1])) === 1);
ok('restores are in the history', (await val(`select count(*)::int from public.audit_events where action='loan_restored_from_backup'`)) === 3);

// ---- Undo --------------------------------------------------------------------------
await as(B);
await refuses('someone else cannot undo', `select public.undo_loan_restore($1)`, [rD], /Only the person/);
await as(A);
await db.query(`select public.undo_loan_restore($1)`, [rD]);
ok('undo brings the removed draft back', (await val(`select status::text from public.loans where id=$1`, [D])) === 'cancelled');
await refuses('undo twice', `select public.undo_loan_restore($1)`, [rD], /already undone/);
await db.query(`select public.record_collection_activity($1,'call','no_answer','',null,null,$2)`, [L1, uuid()]);
await refuses('undo after a later change', `select public.undo_loan_restore($1)`, [r1], /changed after/);
await db.query(`select public.undo_loan_restore($1)`, [r2]);
ok('undo puts the corrected/refinanced state back', (await val(`select status::text from public.loans where id=$1`, [L2])) === 'refinanced');

// ---- A loan with evidence cannot be removed ----------------------------------------
await refuses('loan with evidence cannot be removed', `select public.restore_loan($1,null,'Remove',now(),$2)`, [L1, uuid()], /uploaded evidence/);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
