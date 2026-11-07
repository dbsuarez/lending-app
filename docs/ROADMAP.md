# Lending Manager Roadmap

Last updated: 2026-11-07

This is the implementation progress tracker. The authoritative product and
business requirements remain in `LENDING_MANAGER_SPEC.md`; visual requirements
remain in `LENDING_MANAGER_UI_DESIGN.md`.

## Current status

**Active milestone:** Phase 3 — Payments and synchronization  
**Next deliverable:** Remaining committed PDF documents and a complete mobile-screen audit  
**Production readiness:** Web is live, but the current local feature batch is not yet
deployed. Remaining PDF artifacts, final legal review, and full phone acceptance remain open.

## Phase progress

| Phase | Status | Progress summary |
|---|---|---|
| Phase 0 — Specification and compliance | In progress | Core specification, UI contract, database standards, UI standards, mockup, and PDF reference are present. Several business/legal decisions remain open. |
| Phase 1 — Foundation | Complete | Flutter web/Android structure, FVM, responsive shell, reusable themes, Supabase Auth, PostgreSQL schema, RLS, migrations, owner bootstrap, and encrypted Android outbox are implemented. |
| Phase 2 — Lending core | In progress | Core lending, disbursement, cancellation, early payoff, private evidence, idempotency, and audit events are implemented. Active-loan amendments and refinancing remain. |
| Phase 3 — Payments and sync | In progress | Pending/rejected/verified/reversed states, atomic oldest-due allocation, partial payments, unapplied credit, cash auto-verification, encrypted collection outbox, retry, and borrower conflict detection are implemented. Committed PDF receipts remain. |
| Phase 4 — Collections and documents | In progress | Contractual queues, promises, contact logs, reminders, summary reports, authoritative aging, CSV export, customer status links, evidence, and A4 schedules are implemented. Additional PDFs remain. |
| Phase 5 — Production readiness | In progress | Responsive golden matrix, analyzer/tests, production schema checks, live smoke writes, backup validation, configurable branding, staff provisioning, release APK, emulator acceptance, and Firebase web deployment are complete. Legal review remains. |

## Completed foundation

- [x] Flutter Web and Android project structure using FVM Flutter 3.38.5
- [x] Responsive desktop sidebar and mobile bottom navigation
- [x] Collapsible desktop sidebar
- [x] Path-based web URLs without hash fragments
- [x] Reusable Material 3 theme system with presets and custom palettes
- [x] System, light, and dark theme modes
- [x] Dashboard matching the approved visual direction
- [x] Equal-height responsive dashboard rows and bounded mobile cards
- [x] Search bar, authenticated-user identity, sync/demo status, and version
- [x] Visible release build identifier beside the version (`build YYYYMMDD_HHmm`)
- [x] Shared `YYYY-MM-DD` and `YYYY-MM-DD HH:mm` presentation formats
- [x] Right-aligned currency and numeric presentation where implemented
- [x] Supabase public client configuration kept outside committed source
- [x] Email/password authentication and sign-out
- [x] Organization membership and role-aware RLS
- [x] Production Supabase project linked through versioned migrations
- [x] Owner organization bootstrapped for `dbsuarez@gmail.com`

## Borrowers

- [x] RLS-protected live borrower reads
- [x] Create and edit borrowers
- [x] Archive instead of hard deletion
- [x] Search by borrower name or phone
- [x] Loading, empty, filtered-empty, error, and populated states
- [x] Refresh and retry actions
- [x] Local demo fallback
- [x] Atomic duplicate borrower detection for normalized phone and email
- [x] Borrower detail page with profile, linked loans, and payments
- [x] Borrower loan and payment activity timeline
- [x] Audited borrower archive and restore workflow
- [x] Per-borrower profile, loan, and payment data export
- [x] Audited borrower consent and interim 10-year retention workflow

## Loans

- [x] Integer-centavo flat monthly calculator
- [x] 3%, 6%, 10%, and custom interest rates
- [x] Whole-month terms
- [x] 15/30 and 5/20 payday schedules
- [x] February and short-month clamping
- [x] Borrower selection from live records
- [x] Terms, schedule preview, and review flow
- [x] Responsive live loan list with search and status
- [x] Atomic server-side draft and installment creation
- [x] Server recalculation and schedule-total validation
- [x] Owner/manager authorization checks
- [x] Idempotent client operation identifier
- [x] Audit event for loan-draft creation
- [x] Custom payday editor
- [x] Loan detail Overview and Schedule tabs
- [x] Loan Overview shows total paid, still owed, and payment progress
- [x] Spreadsheet-style Payment Ledger with due date, payment date, payment, ending balance, and status
- [x] Origin-aware loan breadcrumbs and back navigation
- [x] Personal-loan classification with a separate Personal Loans view
- [x] Personal loans excluded from business dashboards, collections, payments, reports, aging, and Ongoing tags
- [x] Explicit confirmation and immutable confirmed-terms snapshot
- [x] Atomic disbursement recording
- [x] Payments, Activity, and Documents loan-detail tabs
- [x] Private PDF/JPG/PNG disbursement evidence attachment (10 MB maximum)
- [x] Draft cancellation with required reason and audit event
- [x] Active-loan auditable due-date amendment workflow with consent and audit history
- [x] Early payoff with future unearned interest waived
- [x] Overpayment carried as unapplied credit without automatic refund
- [x] Refinancing workflow with linked replacement draft and original-loan history

## Payments and synchronization

- [x] Payment entry for Cash, GCash, AUB, MariBank, and PalPay
- [x] Pending Verification payment state and live history
- [x] Rejected payment workflow with required reason and audit event
- [x] Verified and reversed payment workflows
- [x] Atomic server-side allocation to oldest unpaid installment
- [x] Partial payment allocation
- [x] Duplicate-payment protection through organization-scoped operation IDs
- [x] Reversal/correction workflow with reasons and audit history
- [ ] Receipt generation based on committed payment status
- [x] Encrypted Drift/SQLCipher Android outbox database
- [x] Idempotent offline collection-activity queue and explicit retry
- [x] Optimistic conflict detection for mutable borrower edits
- [x] Financial reconciliation attention UI for unapplied credits with audited reversal path

## Collections, reports, and documents

- [x] Live contractual upcoming and past-due installment queue
- [x] Promise-to-pay records
- [x] Contact attempts, outcomes, and no-response tracking
- [x] Respectful reminder templates with copy action
- [x] Live lending and payment summary report screen
- [x] Payment-method count and amount detail report
- [x] Authoritative outstanding-balance aging report
- [x] Cross-platform loan and payment CSV export
- [x] A4 loan schedule based on `Maricar_Origino_Loan_Schedule.pdf`
- [x] Documents hub for per-loan schedule generation
- [ ] Receipt, statement, agreement, and acknowledgment PDFs

## Customer read-only access

- [x] Owner/manager-generated unguessable loan-status links
- [x] Non-expiring access until explicitly revoked
- [x] Sanitized borrower label and no contact details in the public response
- [x] Read-only balance, verified payments, pending payments, and schedule status
- [x] Public RPC uses hashed tokens; raw tokens are never stored
- [x] Link access timestamp and creation audit event
- [x] Link-management list with explicit revocation action

## Settings and operations

- [x] Theme mode and reusable palette controls
- [x] Supabase connection status
- [x] Authenticated sign-out
- [x] Editable business profile and contact details
- [x] Runtime-configurable business/app name, contact details, and document branding source
- [x] Configurable rate and payday presets
- [x] Payment-method configuration
- [x] Existing staff role management with last-owner protection
- [x] Role-constrained staff invitation email and account provisioning workflow
- [x] Organization JSON backup export and encrypted-storage reminder
- [x] Non-destructive backup validation drill with audited owner responsibility
- [x] Audit-event viewer

## Verification evidence

- [x] `fvm flutter analyze` — no issues
- [x] `fvm flutter test` — 15 tests passing
- [x] Production web release build succeeds
- [x] Production migration history matches local migrations through `202611070032`
- [x] Remote Supabase schema lint reports no errors
- [x] Maricar-style A4 schedule rendered and visually inspected
- [x] Live production borrower write verified with an archived smoke record
- [x] Live production loan-draft write verified, then cancelled with an audit reason
- [x] Dashboard golden matrix at 390x844, 1024x768, and 1440x900
- [x] Android release APK build
- [x] Pixel 6a emulator cold-start, local demo dashboard, and More-menu acceptance test
- [x] SQLCipher Android outbox initialized and reported synced on the Pixel 6a emulator
- [x] Read-only production smoke verified approved policy preferences and authoritative aging RPC
- [x] Staff invitation Edge Function deployed to production
- [x] Credential-safe Firebase Hosting deployment with direct-route SPA rewrites

## Decisions required before later phases

- [x] Runtime-configurable business name and production branding source
- [x] Early settlement and overpayment treatment
- [x] Interest treatment on early payoff
- [x] Payment allocation order (oldest due, interest, then principal; penalties currently disabled)
- [x] Bank-transfer verification defaults
- [x] Interim borrower data-retention period and consent requirements
- [x] Document/evidence storage scope and 10 MB-per-file limit
- [x] Weekly encrypted backup and owner recovery responsibility
- [ ] Legal review of agreements, rates, penalties, and collection practices

## Remaining implementation order

1. Perform a full responsive audit of every phone screen before building or installing another APK.
2. Add committed receipts, statements, agreements, and acknowledgments when the PDF artifact runtime is available.
3. Complete legal review.
4. When explicitly requested, build and deploy the current local web feature batch with its build identifier.
