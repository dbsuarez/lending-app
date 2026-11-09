// Migration 202611090044 (settling overpayments) on a local database.
// Run: node tool/backup/overpayment_test.mjs
import { localDb, OWNER_EMAIL } from './lib/localdb.mjs';

const A = '00000000-0000-0000-0000-00000000000a';
const B = '00000000-0000-0000-0000-00000000000b';
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };
const uuid = () => crypto.randomUUID();
const db = await localDb({ users: [{ id: A, email: OWNER_EMAIL }, { id: B, email: 'm@example.test' }] });
const val = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0] ?? {})[0];
const refuses = async (name, sql, params, pattern) => {
  try { await db.query(sql, params); ok(`${name} (should refuse)`, false); }
  catch (e) { ok(`${name} -> "${e.message}"`, pattern.test(e.message), e.message); }
};
const as = (u) => db.query(`select set_config('test.uid',$1,false)`, [u]);
await as(A);
const org = await val(`select organization_id from public.organization_members where user_id=$1`, [A]);
await db.query(`insert into public.organization_members(organization_id,user_id,role,status) values($1,$2,'manager','active')`, [org, B]);
const b = await val(`select public.save_borrower(null,'Over','Payer','0917',null,'Manila')`);
const sched = [{ sequence: 1, due_date: '2026-09-15', principal_centavos: 100000, interest_centavos: 10000, scheduled_centavos: 110000 }];
const loan = await val(`select public.create_loan_draft($1,$2,100000,1000,1,'2026-09-15','{15,30}',$3::jsonb,$4)`, [org, b, JSON.stringify(sched), uuid()]);
await db.query(`select public.activate_loan($1,'2026-09-01','Cash','',$2)`, [loan, uuid()]);
const p = await val(`select public.record_pending_payment($1,114000,'2026-09-15','GCash','',$2,'t')`, [loan, uuid()]);
await db.query(`select public.verify_payment($1)`, [p]);
ok('overpaid 40.00 held as credit', Number(await val(`select unapplied_centavos from public.payments where id=$1`, [p])) === 4000);

await refuses('kept needs a reason', `select public.settle_overpayment($1,'kept','2026-09-20',null,null,'')`, [p], /reason/);
await refuses('refund needs a method', `select public.settle_overpayment($1,'refunded','2026-09-20',null,null,null)`, [p], /how the refund/);
await db.query(`select public.settle_overpayment($1,'refunded','2026-09-20','GCash','REF-1',null)`, [p]);
const row = (await db.query(`select unapplied_centavos u, unapplied_settled_centavos s, unapplied_settlement j from public.payments where id=$1`, [p])).rows[0];
ok('refund settles the whole credit', Number(row.u) - Number(row.s) === 0 && row.j.kind === 'refunded' && row.j.reference === 'REF-1');
await refuses('settling twice', `select public.settle_overpayment($1,'kept','2026-09-20',null,null,'Keep')`, [p], /no overpayment/);
ok('in the history', (await val(`select count(*)::int from public.audit_events where action='overpayment_settled'`)) === 1);
await as(B);
await refuses('someone else cannot undo', `select public.undo_overpayment_settlement($1)`, [p], /Only the person/);
await as(A);
await db.query(`select public.undo_overpayment_settlement($1)`, [p]);
ok('undo reopens the credit', Number(await val(`select unapplied_settled_centavos from public.payments where id=$1`, [p])) === 0);
await db.query(`select public.settle_overpayment($1,'kept','2026-09-20',null,null,'Borrower said keep the change')`, [p]);
ok('kept with a reason', (await val(`select unapplied_settlement->>'reason' from public.payments where id=$1`, [p])) === 'Borrower said keep the change');
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
