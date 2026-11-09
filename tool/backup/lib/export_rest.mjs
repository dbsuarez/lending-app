// Exports an organization through the app's normal API (signed in as the
// owner), so it sees exactly what the app sees and needs no database password.
import { TABLES, OPTIONAL, pkOf, orgColumnOf } from './archive.mjs';

const PAGE = 500; // below the API's 1000-row cap; paging continues until the exact count is reached

export async function signIn({ url, anonKey, email, password }) {
  const r = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anonKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!r.ok) return null;
  const j = await r.json();
  return { token: j.access_token, userId: j.user.id };
}

export function api({ url, anonKey, token }) {
  const headers = { apikey: anonKey, authorization: `Bearer ${token}` };
  return {
    async get(pathAndQuery, extra = {}) {
      const r = await fetch(`${url}/rest/v1/${pathAndQuery}`, { headers: { ...headers, ...extra } });
      if (!r.ok) throw new Error(`Read ${pathAndQuery.split('?')[0]} failed: HTTP ${r.status} ${await r.text()}`);
      return { rows: await r.json(), range: r.headers.get('content-range') };
    },
    async rpc(name, body) {
      const r = await fetch(`${url}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: { ...headers, 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!r.ok) throw new Error(`${name} failed: HTTP ${r.status} ${await r.text()}`);
      return r.json();
    },
    async file(bucket, path) {
      const r = await fetch(`${url}/storage/v1/object/authenticated/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`, { headers });
      if (!r.ok) throw new Error(`Download ${path} failed: HTTP ${r.status}`);
      return new Uint8Array(await r.arrayBuffer());
    },
  };
}

/** All rows of one table for the organization, page by page. */
export async function fetchAll(client, table, orgId) {
  const order = pkOf(table).map((c) => `${c}.asc`).join(',');
  const rows = [];
  let total = Infinity;
  while (rows.length < total) {
    const { rows: page, range } = await client.get(
      `${table}?select=*&${orgColumnOf(table)}=eq.${orgId}&order=${order}&limit=${PAGE}&offset=${rows.length}`,
      { prefer: 'count=exact' },
    );
    total = Number(range?.split('/')[1] ?? page.length);
    if (!page.length) break;
    rows.push(...page);
  }
  if (rows.length !== total) throw new Error(`${table}: read ${rows.length} of ${total} rows`);
  return rows;
}

export async function exportOrganization(client, userId, { includeFiles = true, onProgress = () => {} } = {}) {
  const { rows: members } = await client.get(
    `organization_members?select=organization_id,role&user_id=eq.${userId}&status=eq.active&limit=1`,
  );
  if (!members.length) throw new Error('This account is not an active member of an organization.');
  if (members[0].role !== 'owner') throw new Error('Backups must be made by the owner account.');
  const orgId = members[0].organization_id;
  const tables = {};
  for (const t of TABLES) {
    try {
      tables[t] = await fetchAll(client, t, orgId);
    } catch (e) {
      // A table added by a migration not yet applied to this project.
      if (OPTIONAL.includes(t) && /PGRST205|HTTP 404/.test(e.message)) {
        tables[t] = [];
      } else {
        throw e;
      }
    }
    onProgress(`${t}: ${tables[t].length}`);
  }
  let files = null;
  if (includeFiles) {
    files = [];
    for (const d of tables.loan_documents) {
      files.push({ bucket: 'loan-evidence', path: d.storage_path, bytes: await client.file('loan-evidence', d.storage_path) });
    }
    for (const q of tables.payment_qr_codes) {
      files.push({ bucket: 'payment-qrs', path: q.storage_path, bytes: await client.file('payment-qrs', q.storage_path) });
    }
    onProgress(`files: ${files.length}`);
  }
  const org = tables.organizations[0];
  return { organization: { id: orgId, name: org?.name ?? '' }, tables, files };
}
