// Loads a checked backup into an EMPTY database that already has the app's
// migrations applied, then proves the result matches the backup.
//
// `db` is anything with query(sql, params) -> {rows} (node-postgres or PGlite).
import { TABLES, BALANCE_SQL, balancesFromRows, diffBalances, remapUsers } from './archive.mjs';

const BATCH = 500;

export async function targetColumns(db, table) {
  const r = await db.query(
    `select column_name from information_schema.columns where table_schema='public' and table_name=$1`,
    [table],
  );
  return new Set(r.rows.map((x) => x.column_name));
}

/**
 * A target is "fresh" when it holds nothing, or only the placeholder that
 * the bootstrap migration creates in a new project (one organization with
 * its one owner and no other data). Anything else is refused.
 * Returns the placeholder owner's user id, if there is one.
 */
export async function inspectTarget(db) {
  const busy = [];
  const n = {};
  for (const t of TABLES) {
    n[t] = (await db.query(`select count(*)::int n from public.${t}`)).rows[0].n;
    if (n[t] > 0 && t !== 'organizations' && t !== 'organization_members') busy.push(`${t} (${n[t]})`);
  }
  if (n.organizations > 1 || n.organization_members > 1) busy.push('more than one organization or member');
  if (busy.length) {
    throw new Error(`Target is not empty: ${busy.join(', ')}. Restore only into a new, empty project.`);
  }
  if (!n.organization_members) return { placeholderOwner: null };
  const m = (await db.query(`select user_id::text u, role::text r from public.organization_members`)).rows[0];
  if (m.r !== 'owner') throw new Error('Target has a non-owner member; it is not a fresh project.');
  return { placeholderOwner: m.u };
}

/**
 * @param backup result of readArchive (must be ok)
 * @param userMap {oldUserId: newUserId}
 * @returns report {ok, counts, problems}
 */
export async function restoreInto(db, backup, { userMap = {} } = {}) {
  if (!backup.ok) throw new Error('Backup failed its checks; not restoring.');
  const { placeholderOwner } = await inspectTarget(db);
  // The owner signed up again in the new project: move the backup's owner
  // (and everything they recorded) to that new account.
  const map = { ...userMap };
  const oldOwner = backup.tables.organization_members.find((m) => m.role === 'owner')?.user_id;
  if (placeholderOwner && oldOwner && !Object.keys(map).length && oldOwner !== placeholderOwner) {
    map[oldOwner] = placeholderOwner;
  }
  const tables = remapUsers(backup.tables, map);

  // Columns: the backup must not carry anything the target would silently drop.
  const columns = {};
  for (const t of TABLES) {
    const target = await targetColumns(db, t);
    const used = new Set(tables[t].flatMap((r) => Object.keys(r)));
    const missing = [...used].filter((c) => !target.has(c));
    if (missing.length) {
      throw new Error(`Target ${t} has no column(s) ${missing.join(', ')}. Apply all migrations to the target first.`);
    }
    columns[t] = [...used];
  }

  await db.query('begin');
  try {
    // Rows reference users that only exist in the old project's auth system;
    // replica mode skips foreign-key and trigger checks for this load only.
    await db.query(`set local session_replication_role = replica`);
    // Remove the empty placeholder; the backup brings the real organization.
    await db.query(`delete from public.organization_members`);
    await db.query(`delete from public.organizations`);
    for (const t of TABLES) {
      const rows = tables[t];
      if (!rows.length) continue;
      const cols = columns[t].map((c) => `"${c}"`).join(',');
      for (let i = 0; i < rows.length; i += BATCH) {
        await db.query(
          `insert into public.${t} (${cols}) select ${cols} from jsonb_populate_recordset(null::public.${t}, $1::jsonb)`,
          [JSON.stringify(rows.slice(i, i + BATCH))],
        );
      }
    }
    await db.query('commit');
  } catch (e) {
    await db.query('rollback');
    throw e;
  }
  return { ...(await verifyAgainst(db, backup, tables)), userMap: map };
}

/** Compares a database with a backup: row counts, rows, and loan balances. */
export async function verifyAgainst(db, backup, tables = backup.tables) {
  const problems = [];
  const counts = {};
  for (const t of TABLES) {
    const r = await db.query(`select count(*)::int n from public.${t} where ${t === 'organizations' ? 'id' : 'organization_id'}=$1`, [backup.manifest.organization_id]);
    counts[t] = r.rows[0].n;
    if (r.rows[0].n !== tables[t].length) problems.push(`${t}: ${r.rows[0].n} rows restored, backup has ${tables[t].length}`);
  }
  // Row-by-row: every restored row equals its backup row (compared as jsonb).
  for (const t of TABLES) {
    if (!tables[t].length) continue;
    const join = t === 'organization_members'
      ? 'x.organization_id=b.organization_id and x.user_id=b.user_id'
      : 'x.id=b.id';
    // Each backup value, read through the column's type, equals the stored one.
    const r = await db.query(
      `select count(*)::int n
       from jsonb_array_elements($1::jsonb) e, lateral jsonb_populate_record(null::public.${t}, e) b
       where not exists (
         select 1 from public.${t} x where ${join}
           and (select bool_and((to_jsonb(x)->k) is not distinct from (to_jsonb(b)->k)) from jsonb_object_keys(e) k))`,
      [JSON.stringify(tables[t])],
    );
    if (r.rows[0].n) problems.push(`${t}: ${r.rows[0].n} rows differ from the backup`);
  }
  const balances = balancesFromRows((await db.query(BALANCE_SQL, [backup.manifest.organization_id])).rows);
  for (const d of diffBalances(backup.manifest.balances, balances).slice(0, 10)) problems.push(`balance: ${d}`);
  return { ok: problems.length === 0, counts, problems, balances };
}
