# Lending Manager

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for current implementation progress,
completed work, planned milestones, verification evidence, and open decisions.

Flutter Android/web foundation for a Philippine small-lending business. The current build is a **local development demo**: fixture dashboard data and borrower edits are held in memory and are not synchronized or production-ready.

## Run

1. Install FVM and Flutter 3.38.5.
2. Run `fvm flutter pub get`.
3. Copy `.env.example` to `.env` and add the public Supabase settings.
4. Run `fvm flutter run -d chrome --dart-define-from-file=.env`.
5. Sign in with a Supabase Auth user, or select **Enter local demo**.

`.env` is ignored by Git. Flutter web may contain the public Supabase URL and anon/publishable key, but never a service-role key.
Optional `DEV_LOGIN_EMAIL` and `DEV_LOGIN_PASSWORD` values prefill the local
login form. They are development-only and must not be included in a deployed
web build.

## Implemented

- Material 3 token system, desktop sidebar, mobile navigation, responsive dashboard, accessible chart summary
- Explicit local-demo authentication boundary; no hardcoded credentials or fake synchronization
- Borrower search/create/edit with validation and organization ownership in the domain model
- Flat-monthly loan calculator, 3/6/10% presets, custom rates, whole-month terms, 15/30 and 5/20 patterns
- Deterministic centavo schedule splitting and February/short-month clamping
- Loan terms, schedule, and review workflow; drafts do not create financial obligations
- Initial Supabase PostgreSQL migration, organization membership, RLS, transaction idempotency constraint, and audit table
- Android and web platform projects; unit/widget tests

## Partial or pending

- Drift/SQLite tables and offline outbox; packages are present but financial writes are intentionally not simulated
- Payment posting/allocation RPC, reversals, sync reconciliation, collections workflow, PDFs, reports, backups
- Loan confirmation, disbursement evidence, complete loan detail/history
- Production accessibility/golden matrix, legal/compliance review, Android release build, deployment

The SQL migration deliberately provides read access to organization financial data but no direct client policies for payment/allocation writes. Those writes must go through a future atomic, idempotent server RPC.

## Verification

Run `fvm flutter analyze`, `fvm flutter test`, and `fvm flutter build web`. Financial tests cover the ₱20,000 / 6% / 5-month reference case and leap/non-leap February clamping.

See `docs/LENDING_MANAGER_SPEC.md` and `docs/LENDING_MANAGER_UI_DESIGN.md` for the authoritative requirements. The business specification wins over illustrative mockup values. Rates and penalties are configurable terms, not a claim of legal enforceability.
