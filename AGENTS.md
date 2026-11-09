# Notes for AI assistants working on this repo

Lending Manager: a Flutter app (web on Firebase Hosting, plus an Android APK)
on Supabase (Postgres RPCs and row-level security).

Read before you touch these areas:

- **Web build, `web/`, `firebase.json`, icons, or reports of "blank icons" /
  "old version still showing":** [docs/WEB_ICONS_AND_CACHING.md](docs/WEB_ICONS_AND_CACHING.md).
  Never re-enable icon tree-shaking or a service worker. Verify fixes in a
  browser that has old state, not only against the server.
- **Building and deploying:** [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). Use
  `tool/build_web.ps1` and `tool/build_apk.ps1`, which include a credential
  scan. Never build the public web app with the full `.env`.
- **Database changes:** [docs/DATABASE_STANDARDS.md](docs/DATABASE_STANDARDS.md).
  Push migrations with `tool/db_push.ps1` (dry run first, then `-Apply`).
  Supabase refuses `DELETE`/`UPDATE` without a `WHERE` on API requests
  (safeupdate) but the local PGlite tests do not: use `TRUNCATE` or a `WHERE`,
  and after pushing, call any changed public RPC once through the real API.
- **Backups and restores:** [docs/BACKUP_AND_RESTORE.md](docs/BACKUP_AND_RESTORE.md).
  Take a backup (`node tool/backup/backup.mjs`) before any one-off data fix.
- **After any change to loans or payments:** refresh every view derived from
  them (`lib/app/data_refresh.dart`).
