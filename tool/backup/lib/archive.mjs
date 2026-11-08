// Lending Manager backup archive (format v2), shared by the weekly backup,
// the restore tool and the tests. The app writes the same format
// (lib/features/settings/backup_archive.dart).
//
// A backup is a zip:
//   manifest.json            format, organization, per-table count + sha256,
//                            per-file size + sha256, loan balances at export
//   tables/<table>.json      all rows of that table (JSON array)
//   files/<bucket>/<path>    uploaded documents/evidence (optional)
//
// Checksums are over the exact bytes stored in the zip, so any writer can be
// checked by any reader.
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import { createHash } from 'node:crypto';

export const FORMAT = 'lending-manager-backup-v2';

/** Restore order: parents before children. */
export const TABLES = [
  'organizations',
  'organization_members',
  'borrowers',
  'loans',
  'installments',
  'loan_documents',
  'loan_disbursements',
  'loan_amendments',
  'payments',
  'payment_allocations',
  'payment_corrections',
  'collection_activities',
  'loan_share_links',
  'staff_invitations',
  'audit_events',
];

/** Tables the app cannot work without; a backup missing rows here is useless. */
export const REQUIRED = ['organizations', 'organization_members'];

export const pkOf = (table) =>
  table === 'organization_members' ? ['organization_id', 'user_id'] : ['id'];
export const orgColumnOf = (table) =>
  table === 'organizations' ? 'id' : 'organization_id';

export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

const keyOf = (table, row) => pkOf(table).map((c) => String(row[c])).join('|');
export const sortRows = (table, rows) =>
  [...rows].sort((a, b) => (keyOf(table, a) < keyOf(table, b) ? -1 : keyOf(table, a) > keyOf(table, b) ? 1 : 0));

const num = (v) => (v == null ? 0 : Number(v));

/**
 * Balances per loan, computed exactly like the dashboard/aging reports:
 * per installment, outstanding = max(scheduled - verified allocations, 0).
 */
export function computeBalances(tables) {
  const status = new Map(tables.payments.map((p) => [p.id, p.status]));
  const paidByInst = new Map();
  for (const a of tables.payment_allocations) {
    if (status.get(a.payment_id) !== 'verified') continue;
    const amt = num(a.principal_centavos) + num(a.interest_centavos) + num(a.penalty_centavos);
    paidByInst.set(a.installment_id, (paidByInst.get(a.installment_id) ?? 0) + amt);
  }
  const out = {};
  for (const l of tables.loans) {
    out[l.id] = { status: String(l.status), total: num(l.total_centavos), paid: 0, outstanding: 0 };
  }
  for (const i of tables.installments) {
    const b = out[i.loan_id];
    if (!b) continue;
    const paid = paidByInst.get(i.id) ?? 0;
    b.paid += paid;
    b.outstanding += Math.max(num(i.scheduled_centavos) - paid, 0);
  }
  return out;
}

/** The same calculation in SQL, for checking a database (live or restored). */
export const BALANCE_SQL = `
  select l.id::text loan_id, l.status::text status, l.total_centavos::bigint total,
    coalesce(sum(x.paid),0)::bigint paid, coalesce(sum(greatest(x.scheduled-x.paid,0)),0)::bigint outstanding
  from public.loans l
  left join (
    select i.loan_id, i.scheduled_centavos scheduled, coalesce(sum(
      case when p.status='verified' then pa.principal_centavos+pa.interest_centavos+pa.penalty_centavos else 0 end),0) paid
    from public.installments i
    left join public.payment_allocations pa on pa.installment_id=i.id
    left join public.payments p on p.id=pa.payment_id
    group by i.id
  ) x on x.loan_id=l.id
  where l.organization_id=$1
  group by l.id`;

export function balancesFromRows(rows) {
  const out = {};
  for (const r of rows) {
    out[r.loan_id] = { status: r.status, total: num(r.total), paid: num(r.paid), outstanding: num(r.outstanding) };
  }
  return out;
}

export function totalsOf(balances) {
  let active = 0, loans = 0;
  for (const b of Object.values(balances)) {
    loans++;
    if (b.status === 'active') active += b.outstanding;
  }
  return { loans, outstanding_active_centavos: active };
}

/** Lists balance differences between two balance maps (empty = identical). */
export function diffBalances(expected, actual) {
  const diffs = [];
  for (const id of new Set([...Object.keys(expected), ...Object.keys(actual)])) {
    const e = expected[id], a = actual[id];
    if (!e || !a) { diffs.push(`loan ${id}: ${e ? 'missing after' : 'not in backup'}`); continue; }
    for (const k of ['status', 'total', 'paid', 'outstanding']) {
      if (e[k] !== a[k]) diffs.push(`loan ${id}: ${k} ${e[k]} vs ${a[k]}`);
    }
  }
  return diffs;
}

/**
 * Builds the zip. `tables` maps every table in TABLES to its rows; `files`
 * is a list of {bucket, path, bytes}.
 */
export function buildArchive({ source, organization, schemaVersion, tables, files = null, balances = null }) {
  const entries = {};
  const manifest = {
    format: FORMAT,
    source,
    exported_at: new Date().toISOString(),
    organization_id: organization.id,
    organization_name: organization.name,
    schema_version: schemaVersion ?? null,
    tables: {},
    files_included: files != null,
    files: [],
    balances: balances ?? computeBalances(tables),
  };
  manifest.totals = totalsOf(manifest.balances);
  for (const t of TABLES) {
    const bytes = strToU8(JSON.stringify(sortRows(t, tables[t] ?? [])));
    entries[`tables/${t}.json`] = bytes;
    manifest.tables[t] = { count: (tables[t] ?? []).length, sha256: sha256(bytes) };
  }
  for (const f of files ?? []) {
    entries[`files/${f.bucket}/${f.path}`] = [f.bytes, { level: 0 }];
    manifest.files.push({ bucket: f.bucket, path: f.path, size: f.bytes.length, sha256: sha256(f.bytes) });
  }
  entries['manifest.json'] = strToU8(JSON.stringify(manifest, null, 2));
  return { bytes: zipSync(entries, { level: 6 }), manifest };
}

/**
 * Opens and fully checks a backup. Never throws for a bad backup: returns
 * {ok, problems, manifest, tables, files}. `problems` is human-readable.
 */
export function readArchive(bytes) {
  const problems = [];
  let entries;
  try {
    entries = unzipSync(bytes);
  } catch (e) {
    return { ok: false, problems: [`Not a readable zip file (${e.message})`] };
  }
  if (!entries['manifest.json']) return { ok: false, problems: ['manifest.json is missing'] };
  let manifest;
  try {
    manifest = JSON.parse(strFromU8(entries['manifest.json']));
  } catch {
    return { ok: false, problems: ['manifest.json is not valid JSON'] };
  }
  if (manifest.format !== FORMAT) return { ok: false, problems: [`Unsupported format ${manifest.format}`] };

  const tables = {};
  for (const t of TABLES) {
    const entry = entries[`tables/${t}.json`];
    const meta = manifest.tables?.[t];
    if (!entry || !meta) { problems.push(`${t}: missing`); tables[t] = []; continue; }
    if (sha256(entry) !== meta.sha256) problems.push(`${t}: checksum mismatch (file damaged or edited)`);
    try {
      tables[t] = JSON.parse(strFromU8(entry));
    } catch {
      problems.push(`${t}: not valid JSON`); tables[t] = []; continue;
    }
    if (!Array.isArray(tables[t])) { problems.push(`${t}: not a list`); tables[t] = []; continue; }
    if (tables[t].length !== meta.count) problems.push(`${t}: ${tables[t].length} rows, manifest says ${meta.count}`);
  }
  for (const t of REQUIRED) if (!tables[t]?.length) problems.push(`${t}: no rows`);

  // Every row belongs to the backed-up organization.
  for (const t of TABLES) {
    const col = orgColumnOf(t);
    const strays = tables[t].filter((r) => r[col] !== manifest.organization_id).length;
    if (strays) problems.push(`${t}: ${strays} rows from another organization`);
  }

  // References resolve inside the backup.
  const ids = (t) => new Set(tables[t].map((r) => r.id));
  const loans = ids('loans'), payments = ids('payments'), insts = ids('installments');
  const borrowers = ids('borrowers'), docs = ids('loan_documents');
  const refs = [
    ['loans', 'borrower_id', borrowers],
    ['installments', 'loan_id', loans],
    ['loan_documents', 'loan_id', loans],
    ['loan_disbursements', 'loan_id', loans],
    ['loan_amendments', 'loan_id', loans],
    ['loan_amendments', 'supporting_document_id', docs],
    ['payments', 'loan_id', loans],
    ['payment_allocations', 'payment_id', payments],
    ['payment_allocations', 'installment_id', insts],
    ['payment_corrections', 'payment_id', payments],
    ['collection_activities', 'loan_id', loans],
    ['loan_share_links', 'loan_id', loans],
  ];
  for (const [t, col, set] of refs) {
    const broken = tables[t].filter((r) => r[col] != null && !set.has(r[col])).length;
    if (broken) problems.push(`${t}.${col}: ${broken} rows point to records not in the backup`);
  }
  // Unique keys.
  for (const t of TABLES) {
    const keys = new Set(tables[t].map((r) => keyOf(t, r)));
    if (keys.size !== tables[t].length) problems.push(`${t}: duplicate rows`);
  }

  // Balances recomputed from the rows match what was recorded at export.
  const recomputed = computeBalances(tables);
  if (manifest.balances) {
    for (const d of diffBalances(manifest.balances, recomputed).slice(0, 10)) problems.push(`balance: ${d}`);
  }

  // Files.
  const files = [];
  if (manifest.files_included) {
    const listed = new Set();
    for (const f of manifest.files ?? []) {
      const entry = entries[`files/${f.bucket}/${f.path}`];
      listed.add(f.path);
      if (!entry) { problems.push(`file missing: ${f.path}`); continue; }
      if (sha256(entry) !== f.sha256 || entry.length !== f.size) problems.push(`file damaged: ${f.path}`);
      files.push({ bucket: f.bucket, path: f.path, bytes: entry });
    }
    for (const d of tables.loan_documents) {
      if (!listed.has(d.storage_path)) problems.push(`document without its file: ${d.storage_path}`);
    }
  }

  return { ok: problems.length === 0, problems, manifest, tables, files, balances: recomputed };
}

/** Replaces user ids everywhere (e.g. old owner id -> new account in a new project). */
export function remapUsers(tables, map) {
  if (!map || !Object.keys(map).length) return tables;
  let text = JSON.stringify(tables);
  for (const [from, to] of Object.entries(map)) text = text.split(from).join(to);
  return JSON.parse(text);
}
