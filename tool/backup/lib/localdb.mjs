// An in-memory Postgres (PGlite) with the app's migrations applied and small
// stand-ins for Supabase's auth/storage schemas. Used for restore drills and
// tests: a restore can be proven without touching any real project.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MIGRATIONS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../supabase/migrations');

export function latestMigration() {
  return fs.readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort().at(-1).replace(/\.sql$/, '');
}

/** The bootstrap migration needs the owner's account to exist first. */
export const OWNER_EMAIL = 'dbsuarez@gmail.com';

export async function localDb({ users = [{ id: crypto.randomUUID(), email: OWNER_EMAIL }] } = {}) {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema extensions; create schema storage;
    create function extensions.digest(data text, alg text) returns bytea language sql immutable as
      $$ select sha256(convert_to(data, 'UTF8')) $$;
    create function extensions.gen_random_bytes(n integer) returns bytea language sql volatile as
      $$ select substring(decode(md5(random()::text)||md5(random()::text)||md5(random()::text)||md5(random()::text),'hex') from 1 for n) $$;
    create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}'::jsonb);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
    create function auth.role() returns text language sql stable as $$ select 'authenticated' $$;
    create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
    create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb);
    alter table storage.objects enable row level security;
    create function storage.foldername(name text) returns text[] language sql as $$ select string_to_array(name, '/') $$;
  `);
  for (const u of users) await db.query(`insert into auth.users(id,email) values($1,$2)`, [u.id, u.email]);
  for (const f of fs.readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
    try {
      await db.exec(fs.readFileSync(path.join(MIGRATIONS, f), 'utf8').replace(/create extension[^;]*;/gi, ''));
    } catch (e) {
      throw new Error(`Migration ${f} failed on the local database: ${e.message}`);
    }
  }
  return db;
}
