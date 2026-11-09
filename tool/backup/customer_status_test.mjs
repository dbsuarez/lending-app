// Migration 202611090039 (customer status page) on a local database.
// Run: node tool/backup/customer_status_test.mjs
import { localDb, OWNER_EMAIL } from './lib/localdb.mjs';

const A = '00000000-0000-0000-0000-00000000000a';
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => { cond ? pass++ : fail++; console.log(cond ? 'PASS' : 'FAIL', name, cond ? '' : detail); };
const uuid = () => crypto.randomUUID();
const db = await localDb({ users: [{ id: A, email: OWNER_EMAIL }] });
const val = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0] ?? {})[0];
await db.query(`select set_config('test.uid',$1,false)`, [A]);
const org = await val(`select organization_id from public.organization_members where user_id=$1`, [A]);
await db.query(`update public.organizations set name='Sample Lending', phone='0917 000 0000', email='hi@example.test' where id=$1`, [org]);
const b = await val(`select public.save_borrower(null,'Maria','Dela Cruz','0917 555 0101','m@example.test','Pasig City')`);

// Schedule relative to "today" in Manila so the test does not age.
const today = (await db.query(`select (now() at time zone 'Asia/Manila')::date d`)).rows[0].d;
const day = (offset) => { const d = new Date(today); d.setUTCDate(d.getUTCDate() + offset); return d.toISOString().slice(0, 10); };
const sched = [-20, -5, 10, 25].map((o, i) => ({ sequence: i + 1, due_date: day(o), principal_centavos: 250000, interest_centavos: 37500, scheduled_centavos: 287500 }));
const loan = await val(`select public.create_loan_draft($1,$2,1000000,500,3,$3::date,'{15,30}',$4::jsonb,$5)`, [org, b, day(-20), JSON.stringify(sched), uuid()]);
await db.query(`select public.activate_loan($1,$2::date,'GCash','REL-9',$3)`, [loan, day(-40), uuid()]);
const p1 = await val(`select public.record_pending_payment($1,287500,now(),'GCash','1234 5678 9012',$2,'t')`, [loan, uuid()]);
await db.query(`select public.verify_payment($1)`, [p1]);
await db.query(`select public.record_pending_payment($1,100000,now(),'Cash','',$2,'t')`, [loan, uuid()]); // cash = verified at once
await db.query(`select public.record_pending_payment($1,50000,now(),'GCash','',$2,'t')`, [loan, uuid()]);   // stays pending
const link = await val(`select public.create_loan_share_link($1,'9999-12-31')`, [loan]);
const token = link.token ?? link;

const s = await val(`select public.get_shared_loan_status($1)`, [token]);
ok('old fields still there', s.loan_reference && s.total_centavos === 1150000 && Array.isArray(s.schedule) && Array.isArray(s.payments));
ok('business contacts', s.business.name === 'Sample Lending' && s.business.phone === '0917 000 0000');
ok('terms', s.terms.monthly_rate_basis_points === 500 && s.terms.term_months === 3 && s.terms.installment_count === 4 && s.terms.interest_centavos === 150000);
ok('release', s.release && s.release.released_on === day(-40) && Number(s.release.amount_centavos) === 1000000);
// Paid 2875 + 1000 verified: inst 1 fully, inst 2 has 1000 of 2875 -> past due = 1875 (inst 2), overdue 5 days.
ok('past due amount', Number(s.past_due_centavos) === 187500, s.past_due_centavos);
ok('days past due from the oldest unpaid', s.days_past_due === 5, s.days_past_due);
ok('next due', s.next_due && s.next_due.due_date === day(10) && Number(s.next_due.amount_centavos) === 287500);
ok('amount due now = past due', Number(s.amount_due_now_centavos) === 187500);
ok('outstanding from installments', Number(s.outstanding_centavos) === 1150000 - 387500, s.outstanding_centavos);
const st = Object.fromEntries(s.schedule.map((i) => [i.sequence, i.status]));
ok('schedule states', st[1] === 'paid' && st[2] === 'overdue' && st[3] === 'upcoming' && st[4] === 'upcoming', JSON.stringify(st));
ok('still owed per installment', Number(s.schedule[1].outstanding_centavos) === 187500);
// Payoff today: unpaid principal (10000 - 2500 - paid principal of inst2) + interest due (none left on inst1; inst2 interest paid first).
ok('no payoff amount is given to the borrower', !('payoff_today_centavos' in s) && !JSON.stringify(s).includes('early_payoff'));
const gcash = s.payments.find((p) => p.amount_centavos === 287500);
ok('receipt number and last 4 of the reference only', gcash.receipt_no === 'PR-' + p1.slice(0, 8).toUpperCase() && gcash.reference_last4 === '9012');
ok('applied installments on verified payments', gcash.applied.length >= 1 && gcash.applied[0].sequence === 1);
const pending = s.payments.find((p) => p.status === 'pending');
ok('pending payment has no receipt', pending && pending.receipt_no === null && pending.applied === null);
const text = JSON.stringify(s);
ok('no private details', !text.includes('Pasig') && !text.includes('0917 555') && !text.includes('m@example') && !text.includes('1234 5678'));
// Called twice in one session (temp table reuse).
ok('works again in the same session', (await val(`select public.get_shared_loan_status($1)`, [token])).borrower === s.borrower);

if (process.env.STATUS_JSON_OUT) {
  const fs = await import('node:fs');
  fs.writeFileSync(process.env.STATUS_JSON_OUT, JSON.stringify(s));
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
