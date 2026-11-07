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
build `20261107_1911`.
