# Lending Manager — UI/UX Design Specification

**Version:** 1.0 · **Date:** 2026-11-06 · **Status:** Approved visual direction / implementation specification  
**Target:** Flutter Web (desktop browser) + Flutter Android (APK)  
**Companion:** `LENDING_MANAGER_SPEC.md` (business rules and architecture)

> **Visual source of truth:** The **second** Lending Manager mockup approved by the owner (blue/navy gradient desktop dashboard, bright cobalt actions, white/light-blue cards, and two Android screens). The mockup is conceptual AI artwork, **not compiled Flutter code**. Text, numbers, and illustrations in it are examples, not production data or an exact design system. Use the token and behavior specifications below for implementation. Do not copy mockup arithmetic errors or fake data into production.

## 1. Design intent

Build a polished, credible financial operations tool that is **easy to use during collections**, not a generic admin CRUD interface. It should feel calm, trustworthy, fast, and consistent on both form factors. Prioritize clarity over decoration: financial amounts, borrower identities, payment state, and the next action must be instantly visible. Support Philippine peso (₱), Philippine dates, and 15th/30th or 5th/20th paydays.

**Design principles:** (1) actionable dashboard; (2) obvious primary actions; (3) visible payment/sync states; (4) predictable, reversible operations; (5) accessible contrast and touch targets; (6) responsive layouts built from the same design tokens; (7) no mandatory paid UI tools, icon packs, or illustrations.

## 2. Platform and layout strategy

- **Web / Windows browser:** online-first, desktop-focused, responsive down to tablet widths; hosted as static Flutter Web output on Cloudflare Pages. No separate Windows desktop build in v1.
- **Android:** installable Flutter APK, local-first collection entry with queued synchronization when offline. Same brand and components, navigation adapted for one-handed use.
- **Shared:** Flutter Material 3, one token system, shared domain components and validation, separate adaptive shell layouts.
- **Breakpoints (starting values; verify on devices):** compact <600 logical px; medium 600–1023; expanded >=1024. Use `LayoutBuilder` and constraints rather than relying on device labels.
- **Desktop:** fixed/collapsible navigation sidebar (expanded ~232 px, collapsed ~72 px), sticky top toolbar (~64–72 px), content max width ~1440 px with 24 px gutters; four KPI cards when width permits; responsive 2-column analytics and collections; payment table + loan status section below.
- **Android:** top app bar, 4–5 destinations in bottom navigation, scrollable 2-column KPI grid when width permits, vertically stacked collection cards, sticky/obvious primary action, bottom sheets for quick entry. Use a compact single column on very narrow devices.
- **Tablet:** use a rail or sidebar and 2-column layouts when space allows.

## 3. Brand and design tokens

All values are initial implementation tokens, not claims of measured colors from the AI mockup. Store centrally in `AppTheme` / `ThemeExtension`, not scattered literals.

| Token | Light theme | Usage |
|---|---|---|
| `navy900` | `#0C1C45` | Sidebar/header background |
| `navy800` | `#142B62` | Sidebar gradient midpoint |
| `blue600` | `#1463F3` | Primary action, selected nav |
| `blue500` | `#287DFF` | Primary gradient highlight |
| `violet600` | `#6744DC` | Secondary accents |
| `canvas` | `#F4F7FF` | App background |
| `surface` | `#FFFFFF` | Cards, sheets, tables |
| `surfaceTint` | `#EAF1FF` | Subtle highlighted panels |
| `textPrimary` | `#15223B` | Body and headings |
| `textMuted` | `#64748B` | Secondary copy |
| `border` | `#DFE6F3` | Dividers and outlines |
| `success` | `#168451` | Verified payments, paid |
| `warning` | `#9A6200` | Upcoming / promise reminders |
| `danger` | `#C53040` | Overdue, failed sync, errors |

**Gradients:** sidebar `#0C1C45 → #142B62` vertical; primary action `#287DFF → #1463F3`; hero banner `#2B68E9 → #1547B4`. Avoid large decorative gradients behind dense text. **Radius:** 10 px inputs/chips, 14 px buttons, 16–18 px cards, 22 px hero/sheets. **Spacing:** 4, 8, 12, 16, 24, 32 px. **Elevation:** subtle shadows only on cards and floating elements, preferably `0 4 16` low-opacity navy; use borders to define most cards.

**Typography:** Material 3 text theme, preferably bundled **Inter** (SIL Open Font License; verify asset license in repo) or default system font to avoid runtime network fonts. Headline 26–30/700 desktop, 22–24/700 mobile; card labels 12–14/500; KPI values 20–28/700 with tabular figures where supported; body 14–16. Use `₱1,234.56` consistently and right-align currency in tables. Never communicate payment state with color alone.

**Accessibility:** minimum 48×48 logical-pixel touch targets for mobile actions, keyboard focus and hover states on web, semantic labels for icons and charts, scalable text, high-contrast text on colored backgrounds, screen-reader-friendly tables, clear error copy. Verify WCAG AA contrast, especially colored status chips; adjust colors as necessary.

## 4. Shared component library

Create reusable, themed widgets before implementing pages:

- `AppShell`, `DesktopSidebar`, `AppTopBar`, `MobileBottomNav`, `ResponsiveContent`
- `SummaryKpiCard` (icon, label, currency/count, trend, optional click)
- `SectionCard`, `GradientHeroBanner`, `QuickActionTile`, `EmptyState`, `ErrorState`, `SkeletonState`
- `BorrowerAvatar`, `BorrowerListTile`, `StatusChip`, `SyncStatusIndicator`
- `CurrencyField`, `PercentField`, `DateField`, `PaydaySelector`, `ValidatedFormSection`
- `CollectionDueTile`, `LoanSummaryCard`, `InstallmentTimeline`, `PaymentMethodSelector`
- `MoneyDataTable`, `FilterToolbar`, `ConfirmationDialog`, `AuditHistoryPanel`
- `ResponsiveChartCard` with accessible numeric/table fallback

Do not use a generic Card for everything: emphasize critical amounts, make secondary content quieter, and limit visual nesting. Animations should be subtle (150–250 ms) and respect reduced-motion settings. Prefer Material ink feedback and `AnimatedSwitcher` / `AnimatedContainer` over heavy animation packages.

## 5. Screen specifications

### 5.1 Dashboard — desktop (highest priority)

**Sidebar:** logo/name, Dashboard, Borrowers, Loans, Collections, Payments, Reports, Documents, Settings. Reserve Users & Access for future role-management availability; do not show a working staff-management feature before it exists. Bottom: signed-in owner and last sync state.

**Top bar:** page title or contextual search, global borrower/loan/reference search, notification button (only real alerts), owner menu.

**Hero:** short contextual greeting, collection summary, lightweight original vector/Flutter-drawn illustration or no illustration if it compromises speed/readability.

**KPIs (4):** Outstanding Balance, Collected This Month, Due Today, Overdue. Every figure must come from the ledger and be labeled accurately; distinguish overdue installment amounts from total balance of overdue loans.

**Main row:** Collections Trend chart with time filters; Today's Collections list (borrower, loan ID, amount due, status, open action). **Second row:** Recent Payments table (date/time, borrower, amount, method, reference, verification state); Loan Status Overview with counts and percentages. **Quick actions:** New Loan, Record Payment, View Schedule, Loan Calculator, Reports, Generate Document.

**Behavior:** loading skeletons, meaningful empty states, filtering and drill-down. Dashboard cards link to filtered underlying records. Chart values and percentages must be calculated from real data and use consistent denominators.

### 5.2 Dashboard — Android

Compact branded app bar, 2×2 KPI grid (Outstanding, Collections, Due Today, Overdue), quick actions (New Loan, Record Payment, Borrowers, Calculator), Today's Collections list, and bottom navigation: Home / Borrowers / Loans / Collections / More. Payment recording should be reachable in 1–2 taps. Show last synced time and pending uploads unobtrusively.

### 5.3 Borrowers

Search, filters, borrower cards/table, profile detail, contact information, associated loans, collection activities, document links, payment history. Make borrower status separate from loan/payment status. Respect privacy; never display sensitive contact details on public-facing screens.

### 5.4 Create/Edit Loan — stepper

**Step 1 Terms:** borrower, principal, monthly flat interest (quick presets 3%, 6%, 10%, custom), term in months, start date, first due date, schedule preset 15/30 default, 5/20 alternative, custom, penalty policy (none default), optional notes. Show live computation with explicit formula `principal × monthly rate × months`, total repayable and amount per installment.

**Step 2 Schedule:** actual dated installments, including February and short months; define a deterministic rule for 30th on February (last calendar day) and document it; preview installment totals and rounding adjustment on final installment.

**Step 3 Review:** borrower, amounts, due dates, interest terms, penalty policy, acknowledgments and save. Require confirmation before creating a financial obligation. Do not silently change loan terms after payments exist; use auditable amendments.

### 5.5 Loan details

Header with borrower, loan ID, current status and actions. Tabs: Overview / Schedule / Payments / Activity / Documents. Overview includes principal, agreed flat interest, total contractual amount, received amount, outstanding, next due, and progress bar. Installments show due/paid/partial/overdue separately from collection contact status. Avoid representing loan balance as a simple decrement if allocation or penalties complicate the accounting.

### 5.6 Record payment (critical workflow)

Borrower and loan selection, amount received, method **Cash / GCash / AUB / MariBank / PalPay**, payment date/time, optional reference, optional evidence attachment, note, verification status. Preview allocations and resulting balance before confirmation. Cash can be immediately verified; electronic transfers can be Pending Verification until funds are confirmed. Prevent double-tap submissions, use stable transaction IDs, support offline queue, and create receipts only with accurate payment status. Financial corrections should be reversals with reason and audit trail, not hard deletes.

### 5.7 Collections

Today / Upcoming / Overdue tabs, date and collector filters (collector filters hidden until multi-user launch), borrower quick contact actions, promises to pay, no-response tracking, attempts log. Overdue is calculated from unpaid due installments; **Promise to Pay** and **No Response** are separate collection statuses. Provide respectful reminder templates and avoid harassment or disclosure to third parties.

### 5.8 Penalty settings

Modes: **None (default)** / Fixed / Percentage / Manual. Optional grace period and transparent preview of how penalties are calculated. Never retroactively apply newly enabled penalties to existing loans. Require clear contractual basis and legal review before activating penalty charges; log every assessment, adjustment, waiver, and reversal.

### 5.9 Reports / Documents / Settings

Reports: collections by date and payment method, outstanding balances, overdue aging, borrower payment history; date filters, CSV/PDF export. Documents: loan agreement, schedule, statement, receipt with professional A4 print layout. Settings: business profile, rate presets, schedules, methods, penalties, backup/restore, account security, sync status, appearance; future staff permissions section.

## 6. Responsive behavior details

- Do not shrink desktop tables onto mobile. Replace with vertically stacked cards showing the key values and a detail tap.
- Keep forms single-column on phones; use two columns on desktop where natural.
- Keep primary action visible without obscuring form fields or system navigation.
- On desktop use tooltips, keyboard shortcuts only where useful, hover states, and column sorting; on Android use swipe/long-press only as optional enhancements with visible alternatives.
- Do not use fixed screen heights or rely on a particular Android phone resolution. Test 360×800, 393×873, 800×360, tablet, 1366×768 and 1920×1080.
- Support Android back behavior and web browser history via declarative routing.

## 7. Flutter dependencies (free-first shortlist)

Select one library per purpose and pin versions after compatibility and license checks. Package suggestions are **not** evidence that a package is installed or that its current version has been verified.

| Purpose | Suggested package / approach | Notes |
|---|---|---|
| Core UI | Flutter Material 3 | Built in; main design system |
| State | `flutter_riverpod` | Choose this over adding Bloc simultaneously |
| Navigation | `go_router` | Deep links, desktop/mobile routes |
| Charts | `fl_chart` | Collections and loan status charts |
| Local Android DB | `drift` + SQLite | Prefer typed queries/migrations; check platform-specific setup |
| Backend | `supabase_flutter` | Auth and API client; strict RLS |
| PDF | `pdf`, `printing` | Statements, receipts, A4 output |
| Icons | Material Symbols (built-in) or Lucide Flutter package | Prefer one consistent set; check licensing/version |
| Dates/numbers | `intl` | Locale-aware peso/date formatting |
| Reminders | `flutter_local_notifications` + `timezone` | Android notification permissions and scheduling required |
| Font | Bundled Inter or system font | Verify OFL license and include notice if bundling |

Use Flutter's built-in gradients, `ThemeData`, `Card`, `NavigationRail`, `NavigationBar`, `DataTable`, and animations instead of buying a UI kit. Cloudflare Pages and Supabase are infrastructure services, not Flutter UI add-ons. Their free tiers have limits and may change; no production cost guarantee.

## 8. UX states and trust safeguards

- **Sync states:** Synced, Pending, Syncing, Failed / Needs Attention. Never say “Synced” until server acknowledgment.
- **Payments:** Draft, Pending Verification, Verified, Reversed. Clearly separate payment receipt from transfer screenshot and verified funds.
- **Loan states:** Active, Fully Paid, Closed/Cancelled (as supported by business rules); overdue is derived from installments.
- **Error handling:** Inline validation, actionable recovery, retry for sync failures, explicit conflict-resolution flow; never drop offline transactions silently.
- **Privacy/security:** No account numbers in general dashboards; mask references as appropriate; session lock, RLS, secure attachment access, audit logs, backups. Do not log raw credentials, borrower private data, or financial attachments in analytics.
- **Legal:** Templates and charges must be reviewed for applicable Philippine lending, interest, privacy, and fair collection rules before production use. A polished UI does not imply legal compliance.

## 9. Suggested code organization

```text
lib/
  app/
    app.dart
    router.dart
    theme/
      app_theme.dart
      color_tokens.dart
      spacing_tokens.dart
  core/
    widgets/
    formatting/
    responsive/
    sync/
  features/
    dashboard/
    borrowers/
    loans/
    collections/
    payments/
    reports/
    documents/
    settings/
  data/
    local/
    remote/
    repositories/
  domain/
    models/
    services/
```

Build UI against repository interfaces and realistic fixtures, not hardcoded financial calculations in widgets. Keep business rules in tested domain services. The companion project specification controls loan math and sync semantics when any visual mockup differs.

## 10. Codex implementation sequence

1. Establish Flutter project structure, Material 3 theme/tokens, responsive shell, sidebar and mobile navigation.
2. Implement shared components and dashboard using **clearly labeled fixture data**; produce desktop and Android screenshots for review.
3. Implement Borrowers, Create Loan stepper, Loan Detail, and Payment Recording screens with field validation and reusable states.
4. Wire repositories and financial domain services to local persistence and backend, including verified sync indicators.
5. Implement Collections, Reports, PDFs, Settings, and notifications; add audit and backup UX.
6. Run widget/golden tests, responsive checks, keyboard/accessibility checks, financial calculation tests, offline/sync conflict tests, and build web + APK.

### Acceptance checklist

- [ ] Visual hierarchy closely follows **second** approved mockup, without literal copying of inaccurate sample values.
- [ ] All screens use shared theme tokens; no paid UI dependency or unlicensed asset.
- [ ] Desktop sidebar and mobile bottom navigation work with route history.
- [ ] Layout is readable at required test sizes without overflow.
- [ ] Currency, statuses, due dates, and balances use actual domain data once integrated.
- [ ] Loan form uses flat monthly interest and borrower-specific 15/30, 5/20 or custom paydays.
- [x] Payment method options include Cash, GCash, AUB, MariBank, and PalPay.
- [ ] Penalties default to None; alternative modes are configurable but not retroactive.
- [ ] Offline Android payments remain pending until server-acknowledged; no duplicate posting.
- [ ] Charts have accessible summaries and tables have usable mobile alternatives.
- [ ] PDF statements/receipts print cleanly on white A4 paper.
- [ ] User permissions are owner-only in v1, but data is organization-scoped for future roles.
- [ ] Test evidence, screenshots, dependencies and licenses are recorded before production release.

## 11. Instructions to Codex

**Treat this document as the approved UI design contract.** Reproduce the **second** mockup's visual direction in real Flutter widgets using free, commercially permissible packages. Build adaptive web/Android interfaces from a single design system. Avoid generic default cards, but also avoid decorative clutter. Do not substitute a paid component kit. Do not fake live balances, verification, or synchronization states. When a mockup detail conflicts with business math or safe financial workflows, prioritize `LENDING_MANAGER_SPEC.md` and document the discrepancy. Deliver a working, testable implementation increment with screenshots and a clear changelog rather than only another image mockup.
