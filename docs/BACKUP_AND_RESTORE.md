# Backup and restore

## What a backup contains

One `.zip` file (format `lending-manager-backup-v2`):

| Part | Contents |
|---|---|
| `manifest.json` | business, when it was made, row count and SHA-256 checksum per table, size and checksum per file, every loan's balance at the time |
| `tables/*.json` | every row of all 15 tables: organization, members, borrowers, loans, installments, documents list, money releases, loan corrections, payments, allocations, payment corrections, collection notes, customer links, staff invitations, full history |
| `files/loan-evidence/…` | uploaded receipts, agreements and evidence (unless turned off) |

Rows are read page by page and the total is compared with the server's count, so a large table can never be cut short without notice.

Not in the backup: sign-in accounts and passwords (staff sign up again), app settings stored on each device (theme, filters), and the app itself.

## Making backups

- **Automatic, weekly (this PC):** `tool/backup/backup.mjs`, scheduled by `tool/backup/schedule_weekly.ps1`.
  - Each run: signs in as the owner, exports everything, checks the file, then **rehearses a full restore** on a throw-away local database and compares every row and every loan balance.
  - Keeps the newest 12 in `backups/` (git-ignored) and copies each to `E:\LendingManagerBackups` (a different physical disk).
  - Logs each run to `backups/backup-log.txt` and adds a "backup checked" entry to the app's history.
  - Set up once: `powershell -ExecutionPolicy Bypass -File tool/backup/schedule_weekly.ps1`. Remove it with `-Remove`.
  - Run it now: `node tool/backup/backup.mjs`.
- **From the app:** Settings → **Back up everything** (owner). It makes the same file, saved to Downloads, or on a phone to the folder you pick.

Keep at least one copy off this PC (USB drive or cloud storage you control). The file holds customers' personal data, so store it somewhere private.

## Checking a backup

- App: Settings → **Check a backup**. It verifies every checksum, the links between records and every balance, and says how many loans have changed since the backup was made. It never changes live data.
- PC: `node tool/backup/restore.mjs FILE.zip`, which checks only.
- PC: `node tool/backup/restore.mjs FILE.zip --drill`, which performs a full practice restore on a throw-away database and compares the result. Nothing real is touched.

## Restoring after a disaster

A restore goes into a **new, empty Supabase project**, never over existing data. The tool refuses the production project and any project that already has data.

1. Create a new Supabase project.
2. In it, sign up with the owner's email (`dbsuarez@gmail.com`). The first migration needs that account.
3. Apply the migrations to it: `npx supabase db push --db-url "<new project's connection string>"`.
4. Download the project's SSL certificate (Project Settings → Database → SSL) as `new-ca.crt`.
5. Restore, with its connection string in an environment variable:
   ```
   $env:NEW_DB_URL = "<new project's connection string>"
   $env:NEW_SERVICE_KEY = "<new project's service_role key>"
   node tool/backup/restore.mjs FILE.zip --drill
   node tool/backup/restore.mjs FILE.zip --target-env NEW_DB_URL --ca new-ca.crt --yes `
     --storage-url https://<new-ref>.supabase.co --service-key-env NEW_SERVICE_KEY
   ```
   - The owner's records are moved to the new owner account automatically.
   - Staff: invite them again. To keep their history linked, pass `--map-user OLD_ID=NEW_ID` for each one.
   - After loading, the tool compares counts, every row and every loan balance with the backup. It stops with a list if anything differs.
6. Point the app at the new project: update `SUPABASE_URL` and `SUPABASE_ANON_KEY`, rebuild and deploy.

## Tests

- `node tool/backup/test.mjs`: builds realistic data (payments, a reversal, corrections, early payoff, notes, documents), backs it up, tampers with copies, restores into a new project, and confirms the dashboard and aging report match the original and new payments work.
- `flutter test test/backup_archive_test.dart`: the app's reader and writer.
  - `LIVE_BACKUP_TEST=1` adds a read-only check against the live project.
  - `BACKUP_XCHECK_IN`/`_OUT` cross-checks against the command-line tools.

The "The system cannot find the path specified" lines printed during a drill come from the local practice database starting on Windows. They are harmless.
