# Lending Manager Roadmap

Last updated: 2026-11-09

This is the implementation progress tracker. The authoritative product and
business requirements remain in `LENDING_MANAGER_SPEC.md`; visual requirements
remain in `LENDING_MANAGER_UI_DESIGN.md`.

## Current status

**Active milestone:** Phase 4 — Collections and documents
**Next deliverable:** Legal review of the drafted agreement and policies; Correct Terms
for loans with payments
**Production readiness:** Web and Android are live and current (2026-11-09).
Open: the remaining PDFs, legal review, and turning on the weekly backup task.

## Phase progress

| Phase | Status | Progress summary |
|---|---|---|
| Phase 0 — Specification and compliance | In progress | Core specification, UI contract, database standards, UI standards, mockup, and PDF reference are present. Several business/legal decisions remain open. |
| Phase 1 — Foundation | Complete | Flutter web/Android structure, FVM, responsive shell, reusable themes, Supabase Auth, PostgreSQL schema, RLS, migrations, owner bootstrap, and encrypted Android outbox are implemented. |
| Phase 2 — Lending core | Complete | Core lending, disbursement, cancellation, early payoff (dated, undoable), amendments, refinancing, draft editing, loan and money-release corrections with undo, private evidence, idempotency, and audit events are implemented. Correcting the terms of a loan that already has payments remains (see Next). |
| Phase 3 — Payments and sync | In progress | Pending/rejected/verified/reversed states, atomic oldest-due allocation, partial payments, unapplied credit, cash auto-verification, chosen payment date, payment-detail corrections with undo, late-payment reasons, encrypted collection outbox, retry, and borrower conflict detection are implemented. PDF receipts remain. |
| Phase 4 — Collections and documents | In progress | Contractual queues, promises, contact logs, reminders, summary reports, authoritative aging, CSV export, customer status links, categorized evidence with in-app viewing, and A4 schedules and ledgers are implemented. Receipt, statement, agreement and acknowledgment PDFs remain. |
| Phase 5 — Production readiness | In progress | Responsive golden matrix, analyzer/tests, production schema checks, live smoke writes, full backup with checksums and restore drill, per-loan restore, configurable branding, staff provisioning, release APK, Firebase web deployment, stale-cache protection and update prompt are complete. Legal review and enabling the weekly backup task remain. |

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
- [x] Edit Draft: reopen the create steps prefilled, Before/After review
- [x] Correct Loan: released loans without payments, reason required, undo
- [x] Edit Money Release: date, method, reference, reason required, undo
- [x] Early payoff with a chosen payoff date; Undo Early Payoff (shown only when one exists)
- [x] Loan header: actions wrap on their own row; copy button for the loan number
- [x] Every loan/payment change refreshes Ongoing tags, Collections, Dashboard and aging
- [ ] Correct Terms for loans with payments (re-apply payments, with preview)

## Payments and synchronization

- [x] Payment entry for Cash, GCash, AUB, MariBank, and PalPay
- [x] Pending Verification payment state and live history
- [x] Rejected payment workflow with required reason and audit event
- [x] Verified and reversed payment workflows
- [x] Atomic server-side allocation to oldest unpaid installment
- [x] Partial payment allocation
- [x] Duplicate-payment protection through organization-scoped operation IDs
- [x] Reversal/correction workflow with reasons and audit history
- [x] Record payments with a chosen received date
- [x] Edit payment date, method and reference (reason required, undo, history)
- [x] Reason for late payment: prompted when a payment is after its due date, quick picks, editable later, shown in payment lists
- [x] Receipt generation based on committed payment status
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
- [x] A4 payment ledger
- [x] Evidence on the loan page: categories (release proof, payment proof, late-payment reason / promise, agreement, acknowledgment, other), thumbnails, in-app photo and PDF viewer, change category
- [x] Paperclip evidence count in the Loans list, Documents page and loan Documents tab
- [x] Exports open the system "Save to" picker on Android
- [x] Payment receipt PDF (A5, verified payments only; amount in words; not a BIR official receipt)
- [x] Statement of account PDF (amount due now, past due, unpaid installments only, payments, how to pay; full history stays in the ledger)
- [x] Loan agreement PDF with disclosure and schedule (wording still to be reviewed by counsel)
- [x] Acknowledgment of money release PDF
- [x] Business name and contacts on every PDF (was "LENDING MANAGER")
- [ ] Bulk printing of statements
- [ ] Edit collection notes and promises after saving
- [ ] Readable (PDF/CSV) borrower data export

## Customer read-only access

- [x] Owner/manager-generated unguessable loan-status links
- [x] Non-expiring access until explicitly revoked
- [x] Sanitized borrower label and no contact details in the public response
- [x] Read-only balance, verified payments, pending payments, and schedule status
- [x] Public RPC uses hashed tokens; raw tokens are never stored
- [x] Link access timestamp and creation audit event
- [x] Link-management list with explicit revocation action
- [x] Amount due now / overdue days / next payment banner
- [x] Schedule shows still owed per installment and Overdue / Due today / Upcoming
- [x] Loan Terms tab: amount, release, flat rate, interest, installments, no penalties (no payoff amount shown, owner's decision)
- [x] Payment history with receipt numbers, last 4 of the reference, and a printable receipt
- [x] Business phone and email on the page; spreadsheet import notes never shown

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
- [x] Full backup v2: every table paged, checksums, uploaded files, balances (docs/BACKUP_AND_RESTORE.md)
- [x] Weekly automatic backup with restore drill on this PC, second copy on another disk
- [x] Verified restore into a new project (counts, every row, balances; refuses production)
- [x] Restore one loan from a backup (owner): preview, reason, undo; can remove a loan made after the backup
- [ ] Turn on the weekly backup task on the office PC (`tool/backup/schedule_weekly.ps1`); optional off-site copy
- [x] Audit-event viewer
- [x] Long-press any list filter to make it the default (works on Android)
- [x] Hide/resize table columns, remembered per table
- [ ] Phone cards follow hidden table columns

## Verification evidence

- [x] `fvm flutter analyze` — no issues
- [x] `fvm flutter test` — 65 tests passing
- [x] Database tests on a local Postgres copy (`tool/backup/*.mjs`): backup/restore 17, per-loan restore 20, late reason and evidence categories 11
- [x] Real-data restore rehearsal from production backups
- [x] All 105 icons in use verified to draw from the deployed font
- [x] Production web release build succeeds
- [x] Production migration history matches local migrations through `202611090038`
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

## Next, in order

1. Drafts of the legal documents (agreement, disclosure statement, privacy notice, collection and penalty policy) for the lawyer.
2. Legal review; then finalize the agreement wording in the PDF.
3. Correct Terms for loans that already have payments.
4. Edit collection notes and promises; phone cards follow hidden columns; bulk statements; readable borrower export.
5. Owner: turn on the weekly backup task.

Rules for this work: [WEB_ICONS_AND_CACHING.md](WEB_ICONS_AND_CACHING.md),
[BACKUP_AND_RESTORE.md](BACKUP_AND_RESTORE.md), [DEPLOYMENT.md](DEPLOYMENT.md).
