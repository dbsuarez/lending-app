// Reads connection settings and the owner's sign-in from local, git-ignored
// files at run time. Nothing here is printed or written anywhere.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const PRODUCTION_REF = 'bfrifjiqqlziejocleax';

function readKeyValues(file, sep) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const i = line.indexOf(sep);
    if (i > 0) out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return out;
}

export function appConfig() {
  const env = readKeyValues(path.join(REPO, '.env'), '=');
  const url = process.env.SUPABASE_URL ?? env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY ?? env.SUPABASE_ANON_KEY;
  if (!url || !anonKey) throw new Error('SUPABASE_URL / SUPABASE_ANON_KEY not found in .env');
  return { url: url.replace(/\/$/, ''), anonKey };
}

/** Sign-in candidates, most specific first. */
export function ownerLogins() {
  const env = readKeyValues(path.join(REPO, '.env'), '=');
  const notes = readKeyValues(path.join(REPO, 'docs', 'notes_la'), ':');
  return [
    [process.env.LM_BACKUP_EMAIL, process.env.LM_BACKUP_PASSWORD],
    [env.DEV_LOGIN_EMAIL, env.DEV_LOGIN_PASSWORD],
    [notes.user, notes.pass],
  ].filter(([e, p]) => e && p).map(([email, password]) => ({ email, password }));
}
