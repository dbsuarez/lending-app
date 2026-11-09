// Migration 202611090042 (early payoff rules) on a local database.
// Run: node tool/backup/payoff_modes_test.mjs
import { localDb, OWNER_EMAIL } from './lib/localdb.mjs';

const A = '00000000-0000-0000-0000-00000000000a';
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };
const uuid = () => crypto.randomUUID();
const db = await localDb({ users: [{ id: A, email: OWNER_EMAIL }] });
const val = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0] ?? {})[0];
await db.query(`select set_config('test.uid',$1,false)`, [A]);
const org = await val(`select organization_id from public.organization_members where user_id=$1`, [A]);
const b = await val(`select public.save_borrower(null,'Pay','Off','0917',null,'Manila')`);
// 10,000 at 5%/month for 3 months, twice a month: 6 x (1,666.67 principal + 250 interest).
const dates = ['2026-09-15', '2026-09-30', '2026-10-15', '2026-10-30', '2026-11-15', '2026-11-30'];
const sched = dates.map((d, i) => ({ sequence: i + 1, due_date: d, principal_centavos: i === 5 ? 166665 : 166667, interest_centavos: 25000, scheduled_centavos: (i === 5 ? 166665 : 166667) + 25000 }));
const makeLoan = async () => {
  const id = await val(`select public.create_loan_draft($1,$2,1000000,500,3,'2026-09-15','{15,30}',$3::jsonb,$4)`, [org, b, JSON.stringify(sched), uuid()]);
  await db.query(`select public.activate_loan($1,'2026-09-01','Cash','',$2)`, [id, uuid()]);
  // Pays the first two installments.
  const p = await val(`select public.record_pending_payment($1,383334,'2026-09-30','Cash','',$2,'t')`, [id, uuid()]);
  return id;
};
const loan = await makeLoan();
const q = async (mode) => val(`select public.early_payoff_quote($1,'2026-10-20'::date,$2)`, [loan, mode]);
const waive = await q('waive_future');
const month = await q('current_month');
const all = await q('all_interest');
// Paid off on Oct 20; principal left = 4 x 1,666.67 (minus rounding) = 6,666.66.
ok('principal is the same in every rule', waive.principal_centavos === month.principal_centavos && month.principal_centavos === all.principal_centavos);
ok('waive future: only the Oct 15 interest', waive.earned_interest_centavos === 25000, waive.earned_interest_centavos);
ok('current month: both October cutoffs', month.earned_interest_centavos === 50000, month.earned_interest_centavos);
ok('all interest: all four remaining', all.earned_interest_centavos === 100000, all.earned_interest_centavos);
ok('old 2-argument call = waive future', (await val(`select public.early_payoff_quote($1,'2026-10-20'::date)`, [loan])).payoff_centavos === waive.payoff_centavos);

// Record with "current month" and check the loan closes exactly.
const pid = await val(`select public.record_early_payoff($1,'2026-10-20','GCash','',$2,'t','current_month')`, [loan, uuid()]);
ok('payoff amount charged', Number(await val(`select amount_centavos from public.payments where id=$1`, [pid])) === month.payoff_centavos);
ok('loan fully paid', (await val(`select status::text from public.loans where id=$1`, [loan])) === 'fully_paid');
const left = await val(`select sum(greatest(i.scheduled_centavos - coalesce(x.paid,0),0))::int from public.installments i left join (select pa.installment_id, sum(pa.principal_centavos+pa.interest_centavos) paid from public.payment_allocations pa join public.payments p on p.id=pa.payment_id where p.status='verified' group by 1) x on x.installment_id=i.id where i.loan_id=$1`, [loan]);
ok('nothing left owing', left === 0, left);
ok('November interest waived', (await val(`select sum(interest_centavos)::int from public.installments where loan_id=$1 and due_date>'2026-10-31'`, [loan])) === 0);
ok('rule recorded on the loan', (await val(`select terms_snapshot->>'early_payoff_mode' from public.loans where id=$1`, [loan])) === 'current_month');
await db.query(`select public.undo_early_payoff($1)`, [pid]);
ok('undo restores the schedule', (await val(`select status::text from public.loans where id=$1`, [loan])) === 'active' && (await val(`select sum(interest_centavos)::int from public.installments where loan_id=$1`, [loan])) === 150000);

// All interest: nothing waived.
const pid2 = await val(`select public.record_early_payoff($1,'2026-10-20','GCash','',$2,'t','all_interest')`, [loan, uuid()]);
ok('all interest: total unchanged', Number(await val(`select total_centavos from public.loans where id=$1`, [loan])) === 1150000);
try { await db.query(`select public.early_payoff_quote($1,'2026-10-20'::date,'half')`, [loan]); ok('unknown rule refused', false); }
catch (e) { ok('unknown rule refused', /Unknown payoff rule/.test(e.message)); }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
