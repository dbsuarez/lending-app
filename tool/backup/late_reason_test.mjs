// Migration 202611090038 on a local database. Run: node tool/backup/late_reason_test.mjs
import { localDb, OWNER_EMAIL } from './lib/localdb.mjs';

const A = '00000000-0000-0000-0000-00000000000a';
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };
const uuid = () => crypto.randomUUID();
const db = await localDb({ users: [{ id: A, email: OWNER_EMAIL }] });
const val = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0] ?? {})[0];
const refuses = async (name, sql, params, pattern) => {
  try { await db.query(sql, params); ok(`${name} (should refuse)`, false); }
  catch (e) { ok(`${name} -> "${e.message}"`, pattern.test(e.message), e.message); }
};
await db.query(`select set_config('test.uid',$1,false)`, [A]);
const org = await val(`select organization_id from public.organization_members where user_id=$1`, [A]);
const b = await val(`select public.save_borrower(null,'Late','Payer','0917',null,'Manila')`);
const sched = [1, 2].map((i) => ({ sequence: i, due_date: `2026-10-${i === 1 ? 15 : 30}`, principal_centavos: 500000, interest_centavos: 25000, scheduled_centavos: 525000 }));
const loan = await val(`select public.create_loan_draft($1,$2,1000000,500,1,'2026-10-15','{15,30}',$3::jsonb,$4)`, [org, b, JSON.stringify(sched), uuid()]);
await db.query(`select public.activate_loan($1,'2026-10-01','Cash','',$2)`, [loan, uuid()]);

// Old callers: 7 named arguments still work.
const p1 = await val(`select public.record_pending_payment(p_loan_id=>$1,p_amount_centavos=>525000,p_received_at=>'2026-10-20',p_method=>'GCash',p_reference=>'',p_client_operation_id=>$2,p_device_id=>'t')`, [loan, uuid()]);
ok('7-argument call still records', !!p1 && (await val(`select late_reason from public.payments where id=$1`, [p1])) === null);
const p2 = await val(`select public.record_pending_payment($1,525000,'2026-11-05','GCash','',$2,'t','Payday was delayed')`, [loan, uuid()]);
ok('late reason saved with the payment', (await val(`select late_reason from public.payments where id=$1`, [p2])) === 'Payday was delayed');
ok('late reason in the history', (await val(`select payload->>'late_reason' from public.audit_events where record_id=$1 and action='pending_payment_recorded'`, [p2])) === 'Payday was delayed');
await db.query(`select public.set_payment_late_reason($1,'Hospital emergency')`, [p1]);
ok('reason can be added later', (await val(`select late_reason from public.payments where id=$1`, [p1])) === 'Hospital emergency');
await db.query(`select public.set_payment_late_reason($1,'  ')`, [p1]);
ok('reason can be cleared', (await val(`select late_reason from public.payments where id=$1`, [p1])) === null);
ok('changes are in the history', (await val(`select count(*)::int from public.audit_events where action='payment_late_reason_set'`)) === 2);

// Evidence category.
const doc = await val(`select public.register_loan_document($1,'other',$2,'r.jpg','image/jpeg',5)`, [loan, `${org}/${loan}/r.jpg`]);
await db.query(`select public.set_loan_document_type($1,'payment_evidence')`, [doc]);
ok('category changed', (await val(`select document_type from public.loan_documents where id=$1`, [doc])) === 'payment_evidence');
await db.query(`select public.set_loan_document_type($1,'late_payment_note')`, [doc]);
ok('new category: late-payment reason / promise', (await val(`select document_type from public.loan_documents where id=$1`, [doc])) === 'late_payment_note');
const doc2 = await val(`select public.register_loan_document($1,'late_payment_note',$2,'promise.png','image/png',5)`, [loan, `${org}/${loan}/promise.png`]);
ok('can upload straight into the new category', !!doc2);
await refuses('unknown category', `select public.set_loan_document_type($1,'selfie')`, [doc], /Unknown document category/);
ok('recategorize in the history', (await val(`select count(*)::int from public.audit_events where action='loan_document_recategorized'`)) === 2);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
