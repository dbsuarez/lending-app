# Lending Manager — Product & Technical Specification

**Version:** 1.0 draft  
**Date:** 2026-11-06  
**Status:** Requirements baseline; implementation not yet started  
**Target:** Flutter Web (online-first desktop browser) + Flutter Android (offline-first)

## 1. Purpose

A private lending-management application for a small Philippine lending business. Manage borrowers, loans, installments, collections, overdue accounts, promises to pay, documents, and reports. The owner initially operates the app alone on Android and a Windows PC through the web. Architecture must allow future staff/collectors without exposing other borrowers' records.

### Goals
- Replace manual loan spreadsheets with auditable financial records.
- Prevent lost or double-counted payments, especially during offline sync.
- Make upcoming and overdue collections easy to manage.
- Generate clear borrower statements, receipts, and agreements.
- Keep operating costs low with free, commercially usable software and free-tier-first hosting.

### Out of scope for v1
- Automatic bank/GCash reconciliation or payment initiation.
- Automated harassment-prone collection campaigns, credit scoring, or public borrower blacklists.
- Multi-organization SaaS billing, native Windows application, or offline desktop web mode.
- Automated legal enforcement or assuming a generated document is legally enforceable.

## 2. Confirmed business requirements

| Topic | Requirement |
|---|---|
| Interest | Flat monthly interest calculated on original principal |
| Presets | 3%, 6%, 10% monthly; custom percentage allowed |
| Example | ₱20,000 × 6% × 5 months = ₱6,000 interest; ₱26,000 total |
| Repayments | Twice monthly, default 15th and 30th |
| Alternative | 5th and 20th, or borrower/loan-specific custom dates |
| Missing calendar days | Clamp to last valid day (e.g., Feb 30 → Feb 28/29) |
| Penalties | None by default; optional fixed, percentage, manual modes for new loans |
| Payments | Cash, GCash, AUB, MariBank, PalPay; extensible methods |
| Partial payments | Supported; accurate remaining balance and installment allocations |
| Collections | Overdue, promises to pay, unanswered contact attempts, follow-up history |
| Accounts | Single owner initially; future collectors/managers with scoped permissions |
| Platforms | Flutter Android APK and Flutter Web used from Windows browser |
| Connectivity | Android offline-first; web online-first; cloud synchronization |
| Documents | PDF loan schedules, statements, receipts, agreements and acknowledgments |

**Important:** Interest and penalty presets are configuration choices, not legal approval of any rate. Review Philippine law and applicable registration, consumer protection, interest, data privacy and fair collection obligations before real-money deployment. Do not retroactively apply penalties or rewrite historical agreements.

## 3. Primary user journeys

1. Owner creates borrower, optionally attaches documents and contact details.
2. Owner enters principal, monthly rate, duration, schedule, first due date, and penalty policy; app previews the full schedule and total cost before confirmation.
3. Owner records loan disbursement and any supporting evidence; loan becomes active only after explicit confirmation.
4. Dashboard lists due today, upcoming, overdue, outstanding principal/receivables, and collections.
5. Owner records payment, method, date, reference, proof, and notes; payment is verified or marked pending as appropriate.
6. System allocates verified payment according to a clearly disclosed configurable rule, updates installment status, and generates receipt.
7. Owner logs contact attempts and promise-to-pay dates without falsely treating promises as payments.
8. Android records actions offline and syncs later; web displays reconciled state.
9. Owner exports statements, reports, and backup files; can test restoration.

## 4. Screens and navigation

**Dashboard:** key metrics (amount disbursed, receivables, overdue, collected, upcoming); collection attention list; sync health. Distinguish principal from interest, paid from pending, and overdue installments from overdue borrowers.

**Borrowers:** search, create/edit, contact information, linked loans, payment history, notes, contact consent and privacy controls.

**Loans:** create/edit draft, calculator, terms, installment schedule, loan status, disbursement evidence, agreement PDF. Confirmed loan financial terms are immutable; amendments require a versioned event/consent process.

**Collections:** due/overdue queue; promise-to-pay entries (amount/date/outcome); call/message attempts; respectful reminder templates; no-response marker. A loan can be overdue and have a promise simultaneously.

**Payments:** amount, received date/time, method, reference, proof, pending/verified/rejected status, allocation breakdown, receipt, reversal/correction.

**Reports:** collections by date/method, outstanding balances, aging buckets, expected vs actual receipts, interest and fees separately, export CSV/PDF.

**Documents:** printable A4 loan schedule, receipts, statements, prospective written agreement and existing-loan balance acknowledgment. Documents must reflect actual consent and dates.

**Settings:** rates, payday presets, penalty defaults, payment methods, organization profile, backups, sync status, security, user management (future).

## 5. Loan calculation rules

### Flat monthly calculation

- `interest = principal × (monthly_rate / 100) × term_months`
- `total_repayable = principal + interest`
- For two installments per month: `installment_count = term_months × 2`
- Split total across installments in integer centavos; put any rounding remainder into the final installment.

Example: ₱20,000, 6% monthly, 5 months → ₱6,000 interest; ₱26,000 total; 10 × ₱2,600.

**Clarify before implementation:** Whether terms must be whole months; whether first payment can occur on the same day as disbursement; treatment of early payoff, refinancing, additional disbursements, loan cancellations, and prepayments.

### Dates

- First installment date is explicitly selected, not inferred from disbursement date.
- Payday patterns: `[15,30]`, `[5,20]`, or custom day numbers.
- Clamp an unavailable day to the last calendar day of the month; do not silently shift to next month.
- Use Philippine local date (`Asia/Manila`) for contractual due dates, with UTC timestamps for events.
- Store generated due dates per loan so changing settings does not rewrite old schedules.

### Penalties

- Default `none` for all existing loans and new loans unless explicitly changed.
- `fixed`: configured peso amount per overdue installment, with grace days and one-time/recurrence rules.
- `percentage`: specified base (e.g., overdue unpaid installment), percentage, grace days, frequency and cap.
- `manual`: amount, reason, authorized actor, timestamp, supporting agreement.
- Never silently assess retroactive fees. Validate contractual authority and legal compliance before enabling actual assessment.

### Payment allocation

Proposed default: oldest due unpaid installment first, with principal/interest components recorded separately. Penalty allocation order must be explicitly selected and documented before implementation. Store immutable allocations and reversals, not merely a mutable `balance` field. Pending payments must not reduce verified receivables.

## 6. Data model (logical)

All tenant-owned records carry `organization_id`, UUID primary keys, created/updated timestamps, actor identifiers and soft-delete/archive rules where appropriate.

| Table | Key fields / purpose |
|---|---|
| `organizations` | Business details, locale, default settings |
| `profiles` | Auth user metadata |
| `organization_members` | `organization_id`, `user_id`, role, status; future staff |
| `borrowers` | Identity/contact details, notes, consent/privacy metadata |
| `loans` | Borrower, principal centavos, rate basis, term, signed terms snapshot, status |
| `loan_disbursements` | Amount, date, method, proof, verification |
| `installments` | Loan, sequence, due date, principal/interest breakdown, scheduled amount |
| `payments` | Amount centavos, date, method, reference, verification, device/idempotency key |
| `payment_allocations` | Payment → installment and component amounts |
| `payment_reversals` | Original payment, reversal reason, actor, time |
| `penalty_policies` | Per-loan snapshot of mode, rate/amount, base, grace, recurrence, cap |
| `penalty_events` | Assessment/waiver/correction events |
| `collection_activities` | Loan, contact method, attempt, outcome, notes, actor |
| `payment_promises` | Loan, promised amount/date, status, actual follow-up |
| `documents` | Type, storage pointer, hash, version, generated/signed metadata |
| `audit_events` | Actor, action, record, before/after reference, timestamp |
| `sync_operations` | Client operation ID, device ID, payload version, server acknowledgment |

Use integer centavos for all stored money; decimal/numeric or integer basis points for rates. Never use binary floating-point for persisted financial arithmetic. Index `(organization_id, borrower_id)`, due dates, payment statuses and sync IDs.

## 7. Architecture and hosting

- **Client:** Flutter Android + Flutter Web; responsive but distinct layouts.
- **Android local database:** SQLite with a maintained Flutter integration; encrypted sensitive local data where feasible, with secure key storage.
- **Web:** Online-first. No offline financial writes in v1.
- **Backend:** Supabase PostgreSQL, Auth, Storage, and carefully scoped server-side functions/RPC for authoritative posting of payments and allocations.
- **Hosting:** Cloudflare Pages for compiled Flutter Web static assets.
- **Source control:** Private GitHub repository; no secrets in source or web bundles.
- **Domain:** Free `*.pages.dev` address initially; optional custom domain.
- **Costs:** Free-tier-first, subject to limits, project pausing, provider policy changes and backup requirements. Do not assume free-tier hosting alone is production-grade disaster recovery.

The Flutter web app may contain public/publishable Supabase client configuration only; never embed service-role credentials. Enforce PostgreSQL row-level security on all tenant data and private storage access. Never rely on hidden UI controls for authorization.

## 8. Sync and integrity requirements

- Android writes locally into an outbox transaction with a client-generated UUID and monotonically tracked local state.
- Server validates permissions, loan state, and idempotency key; performs payment posting and allocation atomically in a database transaction.
- Retry is safe; duplicate delivery of the same operation cannot create duplicate payments.
- Server assigns authoritative version/timestamp; client acknowledges and reconciles.
- Avoid last-write-wins for money, terms, and allocations. Conflicts require explicit resolution or compensating events.
- Use tombstones/archiving and version checks for mutable borrower details.
- Show `Offline`, `Pending sync`, `Synced`, and `Needs attention` states prominently.
- Multi-device test: payment recorded offline on Android while web edits borrower/loan; ensure correct reconciliation.
- Generate receipts only from verified committed payment state; optionally issue a clearly labeled provisional offline acknowledgment, not a final receipt.

## 9. Security, privacy, and audit

- Owner sign-in; secure session storage; optional local PIN/biometric unlock on Android.
- Prepare roles: `owner`, `manager`, `collector`, `viewer`, with least-privilege permission checks in backend.
- Row-level security by organization and future assignment scopes.
- Encrypt transport (TLS); protect private documents and payment proof attachments.
- Minimize borrower personal data; provide retention, correction, export and deletion/anonymization procedures subject to recordkeeping obligations.
- Never expose borrower details in public URLs or push notification previews by default.
- Record actor and timestamp for financial edits, reversals, penalties and collection attempts.
- Provide encrypted independent backups with scheduled reminders and periodic restore drills.
- Review Philippine Data Privacy Act and applicable lending/collection regulation with qualified counsel before live use.

## 10. Acceptance tests

1. ₱20,000 at 6% flat monthly for 5 months gives ₱26,000, 10 × ₱2,600.
2. 3%, 6%, 10% and custom rates work; invalid/negative values are rejected.
3. 15/30 and 5/20 schedules generate 10 correct dates for 5 months; February clamp works for leap/non-leap years.
4. A partial verified payment reduces outstanding by exactly its allocated amount; pending payment does not.
5. Replaying a sync request does not double-post money.
6. Two offline payment entries from one device are applied exactly once each on reconnect.
7. Payment reversal restores correct outstanding balance and retains the full audit trail.
8. No-penalty default remains for existing loans; penalty modes do not auto-backdate.
9. Promise-to-pay and no-response statuses do not change payment balances.
10. PDF schedule, statement, receipt, and acknowledgment show accurate dates, totals and borrower details.
11. Unauthorized users cannot access another organization's borrower records or storage objects.
12. Backup export and restore reproduce balances, attachments metadata, and event history.
13. Android works offline for approved collection workflows; web explicitly disallows offline writes.
14. Test mobile and desktop layouts, keyboard navigation, date input and Philippine peso formatting.

## 11. Development milestones

### Phase 0 — Specification & compliance gate
Finalize open business rules, data privacy scope, legal template review, UX wireframes, and test fixtures.

### Phase 1 — Foundation
Flutter monorepo/app structure, responsive shell, Supabase schema and RLS, owner login, SQLite local store, migration framework, CI and environment configuration.

### Phase 2 — Lending core
Borrowers, loan calculator, rate presets, installment schedule, loan confirmation, disbursement tracking and financial unit tests.

### Phase 3 — Payments & sync
Verified/pending payments, partial allocations, offline outbox, server idempotency, conflict handling, corrections and receipts.

### Phase 4 — Collections & documents
Overdue queues, promises, contact logs, respectful reminders, PDFs and reports.

### Phase 5 — Production readiness
Security review, restore drill, multi-device stress tests, audit checks, legal/compliance review, release APK, deploy web.

## 12. Decisions still needed

- Business name and preferred app name/branding.
- Whether any loan terms use fractional months or nonstandard installment counts.
- Loan start date vs first due date rules; early settlement and overpayment handling.
- Whether interest is always fully earned on early payoff or adjusted by agreement.
- Payment allocation order among principal, interest and legally agreed penalties.
- Penalty grace periods, frequency and caps, subject to legal review.
- Whether bank transfers require manual verification by default (recommended yes).
- What borrower identity/contact information is essential, and retention period.
- Whether to attach scanned agreements, receipts and transfer proofs; storage budget.
- Backup frequency, encryption key recovery and restore ownership.
- Hosting account ownership and production deployment credentials.

## 13. Delivery standards

- Use only free packages and assets with licenses allowing commercial use.
- Keep secrets out of git, APK source assets and compiled web bundles.
- Include schema migrations, automated tests, changelog, setup instructions and deployment guide.
- Use deterministic money/date calculations with regression fixtures.
- Do not mark a phase complete without passing its acceptance criteria.
- No production use until backup/restore, sync integrity, access control and compliance checks pass.

---

**Document status:** Planning specification only. No code, accounts, hosting, or deployments have been created by this document.
