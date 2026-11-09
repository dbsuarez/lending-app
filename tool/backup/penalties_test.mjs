// Migration 202611090043 (penalties) on a local database.
// Run: node tool/backup/penalties_test.mjs
import { localDb, OWNER_EMAIL } from './lib/localdb.mjs';
import { TABLES, buildArchive, readArchive, loanStateFromTables, orgColumnOf } from './lib/archive.mjs';
import { restoreInto } from './lib/restore.mjs';

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
// 4 installments of 2,875.00 (2,500 principal + 375 interest), paydays 15/30.
const dates = ['2026-09-15', '2026-09-30', '2026-10-15', '2026-10-30'];
const sched = dates.map((d, i) => ({ sequence: i + 1, due_date: d, principal_centavos: 250000, interest_centavos: 37500, scheduled_centavos: 287500 }));
async function loanWith(policy) {
  const id = await val(`select public.create_loan_draft($1,$2,1000000,750,2,'2026-09-15','{15,30}',$3::jsonb,$4)`, [org, b, JSON.stringify(sched), uuid()]);
  if (policy) await db.query(`select public.set_loan_penalty_policy($1,$2::jsonb)`, [id, JSON.stringify(policy)]);
  await db.query(`select public.activate_loan($1,'2026-09-01','Cash','',$2)`, [id, uuid()]);
  return id;
}
const charges = (loan) => val(`select coalesce(json_agg(json_build_object('seq',i.sequence,'date',c.charge_date,'amt',c.amount_centavos,'w',c.waived_at is not null) order by c.charge_date, i.sequence),'[]') from public.penalty_charges c join public.installments i on i.id=c.installment_id where c.loan_id=$1`, [loan]);
const total = (loan) => val(`select total_centavos::int from public.loans where id=$1`, [loan]);

// ---- Policy -----------------------------------------------------------------
const fixed = await loanWith({ mode: 'fixed', amount_centavos: 10000, grace_days: 3 });
await refuses('policy is fixed once released', `select public.set_loan_penalty_policy($1,'{"mode":"none"}'::jsonb)`, [fixed], /draft/);
await refuses('fixed needs an amount', `select public._clean_penalty_policy('{"mode":"fixed"}'::jsonb)`, [], /amount/);

// ---- Automatic charges: due + 3 grace days, then every cutoff while unpaid ----
await val(`select public._assess_penalties($1,'2026-10-01')`, [fixed]);
let c = await charges(fixed);
ok('installment 1: Sep 18 (grace) and Sep 30 (cutoff)', c.length === 2 && c[0].date === '2026-09-18' && c[1].date === '2026-09-30', JSON.stringify(c));
ok('installment 2 not yet (grace runs to Oct 3)', c.every((x) => x.seq === 1));
ok('loan total grows by the penalties', (await total(fixed)) === 1150000 + 20000);
await val(`select public._assess_penalties($1,'2026-10-01')`, [fixed]);
ok('assessing again charges nothing twice', (await charges(fixed)).length === 2);

// ---- Payment order: penalty, interest, principal (oldest installment first) ----
const p = await val(`select public.record_pending_payment($1,15000,'2026-10-02','GCash','',$2,'t')`, [fixed, uuid()]);
await db.query(`select public.verify_payment($1)`, [p]);
let alloc = (await db.query(`select penalty_centavos::int pe, interest_centavos::int i, principal_centavos::int pr from public.payment_allocations where payment_id=$1`, [p])).rows[0];
ok('a small payment goes to the penalty first', alloc.pe === 15000 && alloc.i === 0 && alloc.pr === 0, JSON.stringify(alloc));
const p2 = await val(`select public.record_pending_payment($1,292500,'2026-10-02','GCash','',$2,'t')`, [fixed, uuid()]);
await db.query(`select public.verify_payment($1)`, [p2]);
alloc = (await db.query(`select penalty_centavos::int pe, interest_centavos::int i, principal_centavos::int pr from public.payment_allocations where payment_id=$1`, [p2])).rows[0];
ok('then the rest of the penalty, interest, principal', alloc.pe === 5000 && alloc.i === 37500 && alloc.pr === 250000, JSON.stringify(alloc));

// Installment 1 is now paid: no more charges for it.
await val(`select public._assess_penalties($1,'2026-10-20')`, [fixed]);
c = await charges(fixed);
const later = c.filter((x) => x.date > '2026-10-01');
ok('paid installment stops accruing', later.every((x) => x.seq !== 1), JSON.stringify(later));
ok('installment 2: Oct 3 and Oct 15; installment 3: Oct 18', JSON.stringify(later.map((x) => `${x.seq}@${x.date}`)) === JSON.stringify(['2@2026-10-03', '2@2026-10-15', '3@2026-10-18']), JSON.stringify(later));

// ---- Waive ----------------------------------------------------------------------
const toWaive = await val(`select c.id from public.penalty_charges c join public.installments i on i.id=c.installment_id where c.loan_id=$1 and i.sequence=2 order by c.charge_date limit 1`, [fixed]);
const before = await total(fixed);
await refuses('waive needs a reason', `select public.waive_penalty_charge($1,'')`, [toWaive], /reason/);
await db.query(`select public.waive_penalty_charge($1,'First time, forgiven')`, [toWaive]);
ok('waiving lowers the total', (await total(fixed)) === before - 10000);
const paidCharge = await val(`select c.id from public.penalty_charges c join public.installments i on i.id=c.installment_id where c.loan_id=$1 and i.sequence=1 limit 1`, [fixed]);
await refuses('a paid penalty cannot be waived', `select public.waive_penalty_charge($1,'Too late')`, [paidCharge], /already been paid/);
await val(`select public._assess_penalties($1,'2026-10-20')`, [fixed]);
ok('a waived charge is not charged again', (await charges(fixed)).filter((x) => x.seq === 2).length === 2);

// ---- Percentage of the overdue amount --------------------------------------------
const pct = await loanWith({ mode: 'percentage', rate_basis_points: 500, grace_days: 3 });
await val(`select public._assess_penalties($1,'2026-09-20')`, [pct]);
c = await charges(pct);
ok('5% of the unpaid 2,875.00 = 143.75', c.length === 1 && Number(c[0].amt) === 14375, JSON.stringify(c));

// ---- Manual and none -----------------------------------------------------------
const manual = await loanWith({ mode: 'manual', grace_days: 3 });
await val(`select public._assess_penalties($1,'2026-12-31')`, [manual]);
ok('manual: nothing charged automatically', (await charges(manual)).length === 0);
const inst = await val(`select id from public.installments where loan_id=$1 and sequence=1`, [manual]);
await db.query(`select public.add_penalty_charge($1,5000,'Missed two reminders')`, [inst]);
ok('manual: added by hand', (await charges(manual)).length === 1 && (await total(manual)) === 1155000);
const none = await loanWith(null);
await val(`select public._assess_penalties($1,'2026-12-31')`, [none]);
ok('loans without a policy are never charged', (await charges(none)).length === 0);
const noneInst = await val(`select id from public.installments where loan_id=$1 and sequence=1`, [none]);
await refuses('no manual penalty on a loan made without penalties', `select public.add_penalty_charge($1,5000,'Late')`, [noneInst], /without penalties/);

// ---- Everything else sees penalties ------------------------------------------------
const quote = await val(`select public.early_payoff_quote($1,'2026-10-20'::date,'waive_future')`, [fixed]);
ok('early payoff includes unpaid penalties', Number(quote.penalty_centavos) > 0 && Number(quote.payoff_centavos) === Number(quote.principal_centavos) + Number(quote.earned_interest_centavos) + Number(quote.penalty_centavos));
const link = await val(`select public.create_loan_share_link($1,'9999-12-31')`, [fixed]);
const s = await val(`select public.get_shared_loan_status($1)`, [link.token ?? link]);
ok('customer page shows the policy and the penalties', s.terms.penalties === 'fixed' && Number(s.terms.penalties_charged_centavos) > 0 && s.schedule.some((x) => Number(x.penalty_centavos) > 0));

// ---- Backups and restore carry penalties ------------------------------------------
const tables = {};
for (const t of TABLES) tables[t] = (await db.query(`select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) j from public.${t} x where ${orgColumnOf(t)}=$1`, [org])).rows[0].j;
const backup = readArchive(buildArchive({ source: 'test', organization: { id: org, name: 'T' }, tables }).bytes);
ok('backup with penalties passes every check', backup.ok, backup.problems.join('; '));
const dst = await localDb();
const r = await restoreInto(dst, backup);
ok('full restore matches, penalties included', r.ok && r.counts.penalty_charges === tables.penalty_charges.length, r.problems.join('; '));
const preview = await val(`select public.loan_restore_preview($1,$2::jsonb)`, [fixed, JSON.stringify(loanStateFromTables(tables, fixed))]);
ok('single-loan restore preview of own data changes nothing', JSON.stringify(preview.now) === JSON.stringify(preview.after));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
