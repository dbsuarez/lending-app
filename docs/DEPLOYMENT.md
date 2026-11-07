# Web Deployment

Production web hosting uses Firebase Hosting project `lending-manager-suarez`.

Live URL: https://lending-manager-ph.web.app

## Build safety

Do not build the public web app with `--dart-define-from-file=.env` because the
local file can contain development login credentials. Public builds must define
only:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` (the publishable client key)
- `APP_ENV=production`
- `PUBLIC_APP_URL=https://lending-manager-ph.web.app`
- `BUILD_ID=YYYYMMDD_HHmm` (for example, `20261107_1829`)

Confirm that neither `DEV_LOGIN_EMAIL` nor `DEV_LOGIN_PASSWORD` occurs anywhere
under `build/web` before deployment.

`tool/build_web.ps1` does all of the above in one step: it reads the two public
values from `.env` without printing them, stamps `BUILD_ID` in Asia/Taipei time,
builds, injects the public values into `build/web/status.html`, and fails if any
development credential key or value is found under `build/web`:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web.ps1
```

## Android APK

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1 -Install
```

Builds a release APK (arm64) with the same public-only defines, scans the
compiled snapshot for dev credentials, and replaces the app on the connected
phone with `adb install -r` (keeps app data; stops instead of uninstalling if
signatures differ). The main `AndroidManifest.xml` must declare `INTERNET`:
the Flutter template only declares it for debug/profile, so a release build
without it shows "could not be loaded" everywhere.

## Customer status page

Customer status links (`/s/<token>`) are served by `web/status.html`, a
self-contained HTML page (about 14 KB) rather than the Flutter app, so it loads
quickly on customers' phones. It calls only the public, token-checked
`get_shared_loan_status` and `get_shared_business_name` RPCs. The
`__SUPABASE_URL__` / `__SUPABASE_ANON_KEY__` placeholders are filled by
`tool/build_web.ps1`; a build that skips that step shows "This page is not
configured" instead of loan data. `firebase.json` rewrites `/s/**` to this page
before the catch-all Flutter rewrite.

## Release order: migrations before the app

When a batch adds a migration that the app reads (new columns or RPCs), apply
the migration to production **before** deploying the web build or installing
an APK. Example: `202611070033_transaction_undo.sql` adds
`loan_disbursements.voided_at` and `collection_activities.undone_at`; an app
build that queries them fails on Loans and Collections if the migration is not
live yet.

Migrations can be checked locally first by applying the whole
`supabase/migrations` chain to an in-process Postgres (PGlite) with stub
`auth`/`storage` schemas; the undo migration was verified this way
(23 behavioural checks) before release.

## Deploy

After a verified release build:

```powershell
firebase deploy --only hosting --project lending-manager-suarez
```

Firebase rewrites all routes to `index.html`, allowing direct navigation to
Flutter routes such as `/login` and `/s/<customer-token>`.

Static hashed assets use long-lived caching. `index.html`, the application
bundle, bootstrap script, service worker, and version metadata are never cached
long-term so new deployments become available promptly.

## Supabase CLI

The production project reference is `bfrifjiqqlziejocleax`. The normal linked
workflow is:

```powershell
npx supabase login
npx supabase link --project-ref bfrifjiqqlziejocleax
npx supabase db push --linked
```

If the linked management operation returns HTTP 403 for the signed-in Supabase
account, use the transaction/pooler database URL supplied by the project owner:

```powershell
npx supabase db push --yes --db-url "postgresql://postgres.bfrifjiqqlziejocleax:<DB_PASSWORD>@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres"
```

Treat the database password as an ephemeral secret: retrieve it from the owner
or an approved secret store, do not commit it, and do not paste it into logs or
handoff documents. Migration `202611070032_personal_loans.sql` has already been
applied to production; the corresponding Flutter UI was deployed to the web in
build `20261107_1911`. Migration `202611070033_transaction_undo.sql` (undo)
was applied on 2026-11-07 and web build `20261107_2133` deployed after it.
