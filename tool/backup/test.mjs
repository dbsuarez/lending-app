// End-to-end proof of backup -> check -> restore -> compare, entirely on
// local in-memory databases. Run: node tool/backup/test.mjs
import { strToU8, unzipSync, zipSync } from 'fflate';
import { TABLES, BALANCE_SQL, balancesFromRows, buildArchive, readArchive, diffBalances, orgColumnOf } from './lib/archive.mjs';
import { restoreInto, verifyAgainst } from './lib/restore.mjs';
import { remapUsers } from './lib/archive.mjs';
import { localDb, latestMigration, OWNER_EMAIL } from './lib/localdb.mjs';

const A = '00000000-0000-0000-0000-00000000000a'; // owner (bootstrap email)
const B = '00000000-0000-0000-0000-00000000000b'; // staff
const C = '00000000-0000-0000-0000-00000000000c'; // owner's new account in the new project
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };
const uuid = () => crypto.randomUUID();

function schedule(principal, rateBp, term) {
  const interest = Math.round(principal * rateBp * term / 10000), total = principal + interest;
  const n = term * 2, base = Math.floor(total / n), baseP = Math.floor(principal / n);
  let used = 0, usedP = 0; const out = [];
  for (let i = 0; i < n; i++) {
    const amt = i === n - 1 ? total - used : base, p = i === n - 1 ? principal - usedP : baseP;
    const m = 9 + Math.floor(i / 2);
    out.push({ sequence: i + 1, due_date: `2026-${String(m).padStart(2, '0')}-${i % 2 ? 28 : 15}`,
      principal_centavos: p, interest_centavos: amt - p, scheduled_centavos: amt });
    used += amt; usedP += p;
  }
  return out;
}

// ---- 1. A realistic source database --------------------------------------
const src = await localDb({ users: [{ id: A, email: 'dbsuarez@gmail.com' }, { id: B, email: 'staff@example.test' }] });
const val = async (sql, p = []) => Object.values((await src.query(sql, p)).rows[0] ?? {})[0];
const as = (uid) => src.query(`select set_config('test.uid',$1,false)`, [uid]);
const org = await val(`select organization_id from public.organization_members where user_id=$1`, [A]);
await src.query(`insert into public.organization_members(organization_id,user_id,role,status) values($1,$2,'collector','active')`, [org, B]);
await as(A);
const loans = [];
for (let k = 0; k < 4; k++) {
  const b = await val(`select public.save_borrower(null,$1,'Test','0917',null,'Manila')`, [`Borrower${k}`]);
  const l = await val(`select public.create_loan_draft($1,$2,1000000,600,2,'2026-09-15','{15,28}',$3::jsonb,$4)`,
    [org, b, JSON.stringify(schedule(1000000, 600, 2)), uuid()]);
  loans.push(l);
}
// Loan 0: active, two verified payments, one reversed, one payment correction.
await src.query(`select public.activate_loan($1,'2026-09-01','GCash','R1',$2)`, [loans[0], uuid()]);
const p1 = await val(`select public.record_pending_payment($1,280000,now(),'GCash','',$2,'test')`, [loans[0], uuid()]);
await src.query(`select public.verify_payment($1)`, [p1]);
const p2 = await val(`select public.record_pending_payment($1,150000,now(),'GCash','',$2,'test')`, [loans[0], uuid()]);
await src.query(`select public.verify_payment($1)`, [p2]);
const p3 = await val(`select public.record_pending_payment($1,50000,now(),'GCash','',$2,'test')`, [loans[0], uuid()]);
await src.query(`select public.verify_payment($1)`, [p3]);
await src.query(`select public.reverse_payment($1,'Bounced transfer')`, [p3]);
await src.query(`select public.correct_payment_details($1,'2026-09-14 10:00+08',null,null,'Paid earlier')`, [p2]);
await src.query(`select public.record_collection_activity($1,'call','promised','Will pay Friday','2026-10-02',140000,$2)`, [loans[0], uuid()]);
await src.query(`select public.create_loan_share_link($1,'9999-12-31')`, [loans[0]]);
await src.query(`select public.register_loan_document($1,'payment_evidence',$2,'receipt.jpg','image/jpeg',5)`, [loans[0], `${org}/${loans[0]}/receipt.jpg`]);
// Loan 1: active, money release corrected, one pending payment.
await src.query(`select public.activate_loan($1,'2026-09-01','Cash','',$2)`, [loans[1], uuid()]);
await src.query(`select public.correct_disbursement($1,'2026-08-25','Cash','',$2,$3)`, [loans[1], 'Released Aug 25', uuid()]);
await src.query(`select public.record_pending_payment($1,100000,now(),'Cash','',$2,'test')`, [loans[1], uuid()]);
// Loan 2: settled early. Loan 3: draft.
await src.query(`select public.activate_loan($1,'2026-09-01','GCash','R3',$2)`, [loans[2], uuid()]);
await src.query(`select public.record_early_payoff($1,'2026-09-20','GCash','R4',$2,'test')`, [loans[2], uuid()]);

// ---- 2. Back it up ----------------------------------------------------------
async function dump(db, orgId) {
  const tables = {};
  for (const t of TABLES) {
    const r = await db.query(`select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) j from public.${t} x where ${orgColumnOf(t)}=$1`, [orgId]);
    tables[t] = r.rows[0].j;
  }
  return tables;
}
const tables = await dump(src, org);
const sqlBalances = balancesFromRows((await src.query(BALANCE_SQL, [org])).rows);
const receipt = strToU8('JPEG!');
const { bytes } = buildArchive({
  source: 'test', organization: { id: org, name: 'Test Org' }, schemaVersion: latestMigration(),
  tables, balances: sqlBalances,
  files: [{ bucket: 'loan-evidence', path: `${org}/${loans[0]}/receipt.jpg`, bytes: receipt }],
});
ok('every established table has rows to prove (except optional tables)', TABLES.filter((t) => !['staff_invitations','penalty_charges','payment_qr_codes'].includes(t)).every((t) => tables[t].length > 0),
  TABLES.map((t) => `${t}=${tables[t].length}`).join(' '));

// ---- 3. Check it ------------------------------------------------------------
const backup = readArchive(bytes);
ok('fresh backup passes every check', backup.ok, backup.problems?.join('; '));
ok('balances recomputed from the file match the database', diffBalances(sqlBalances, backup.balances).length === 0);
ok('settled loan has nothing outstanding', backup.balances[loans[2]].outstanding === 0 && backup.balances[loans[2]].status === 'fully_paid');
ok('reversed payment does not count', backup.balances[loans[0]].paid === 430000, backup.balances[loans[0]].paid);

const tamper = (fn) => { const e = unzipSync(bytes); fn(e); return readArchive(zipSync(e)); };
let t = tamper((e) => { e['tables/payments.json'] = strToU8(new TextDecoder().decode(e['tables/payments.json']).replace('280000', '290000')); });
ok('edited payment is caught by checksum', !t.ok && t.problems.some((p) => /payments: checksum/.test(p)), t.problems.join('; '));
t = tamper((e) => { delete e[`files/loan-evidence/${org}/${loans[0]}/receipt.jpg`]; });
ok('missing uploaded file is caught', !t.ok && t.problems.some((p) => /file missing/.test(p)));
t = tamper((e) => { delete e['tables/installments.json']; });
ok('missing table is caught', !t.ok && t.problems.some((p) => /installments: missing/.test(p)));
ok('not a zip is reported, not thrown', readArchive(strToU8('{"format":"x"}')).ok === false);

// ---- 4. Restore into a new, empty project -------------------------------------
const dst = await localDb({ users: [{ id: C, email: OWNER_EMAIL }] }); // owner signed up again: new id
const report = await restoreInto(dst, backup);
ok('restore: counts, rows and balances all match', report.ok, report.problems.join('; '));
ok('restore: owner moved to the new account automatically', report.userMap[A] === C && (await dst.query(`select role::text r from public.organization_members where user_id=$1`, [C])).rows[0]?.r === 'owner');

// The restored copy works: the app's own reports give the same answers.
await dst.query(`select set_config('test.uid',$1,false)`, [C]);
const dash = async (db) => (await db.query(`select public.organization_dashboard_summary('2026-11-01') j`)).rows[0].j;
const aging = async (db) => (await db.query(`select public.organization_aging_report('2026-11-01') j`)).rows[0].j;
ok('restored dashboard equals original', JSON.stringify(await dash(dst)) === JSON.stringify(await dash(src)), JSON.stringify([await dash(dst), await dash(src)]));
ok('restored aging equals original', JSON.stringify(await aging(dst)) === JSON.stringify(await aging(src)));
// And keeps working: record and verify a new payment on the restored copy.
const np = (await dst.query(`select public.record_pending_payment($1,100000,now(),'GCash','',$2,'test') id`, [loans[0], uuid()])).rows[0].id;
await dst.query(`select public.verify_payment($1)`, [np]);
const after = balancesFromRows((await dst.query(BALANCE_SQL, [org])).rows);
ok('restored copy accepts new payments', after[loans[0]].paid === 530000, after[loans[0]].paid);

// ---- 5. Safety --------------------------------------------------------------
let refused = '';
try { await restoreInto(dst, backup); } catch (e) { refused = e.message; }
ok('refuses to restore over existing data', /not empty/.test(refused), refused);
const bad = tamper((e) => { e['tables/loans.json'] = strToU8('[]'); });
refused = '';
try { await restoreInto(await localDb(), bad); } catch (e) { refused = e.message; }
ok('refuses a backup that failed its checks', /failed its checks/.test(refused), refused);

const dst2 = await localDb();
const r2 = await restoreInto(dst2, backup);
await dst2.query(`update public.installments set due_date=due_date+1 where id=(select id from public.installments limit 1)`);
const v2 = await verifyAgainst(dst2, backup, remapUsers(backup.tables, r2.userMap));
ok('a single changed date after restore is detected', !v2.ok && v2.problems.some((p) => /installments: 1 rows differ/.test(p)), v2.problems.join('; '));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
