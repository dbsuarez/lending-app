# UI_STANDARDS.md - Reusable UI and UX Standards

> Applies to all UI work. Read with `AGENTS.md` and `TECH_STACK.md`. These standards are technology-aligned but project-agnostic. Features marked "where appropriate" are conditional, not required on every screen.

## 2. Record management - no inline editing

- Never create or edit records directly inside a table row, grid cell, or list item.
- Do not use editable table cells, inline text inputs, or inline save/cancel controls for record management.
- Tables are for viewing, searching, filtering, sorting, selecting, and navigating records.
- Use **modal dialogs for simple create/edit forms**, such as a few straightforward fields with minimal dependencies.
- Use **dedicated pages for complex create/edit forms**, such as multi-section forms, nested entities, multi-step workflows, large sets of fields, or complex validation.
- Row action buttons may open a modal or navigate to a dedicated form page. Do not expand a row into an editable form.
- Use a confirmation dialog for destructive actions, with clear information about the affected record and consequences.
- Use explicit Save and Cancel actions. Warn about unsaved changes when closing or navigating away from forms where data would be lost.
- Validate on the client for usability and on the server for correctness. Show field-level validation and actionable submission errors.
- Disable duplicate submissions while a request is in progress. Display clear success or failure feedback and refresh affected views after successful changes.
- Bulk operations, when needed, must use explicit selection and a separate confirmation or workflow, not inline editing.

## 3. UI and UX consistency

- Use React, TypeScript, and MUI as defined in `TECH_STACK.md` unless a project explicitly chooses a different stack.
- Use a centralized MUI theme for colors, typography, spacing, component variants, and responsive breakpoints.
- Reuse shared form fields, dialogs, page headers, status indicators, and feedback components where useful.
- Design responsive layouts for desktop, tablet, and mobile. Ensure dialogs remain usable on small screens; use full-screen dialogs or dedicated pages where appropriate.
- Use accessible labels, keyboard navigation, visible focus states, semantic structure, and adequate contrast.
- Every data view should handle loading, empty, error, and populated states.
- Provide clear search and filter controls; use server-side pagination, filtering, and sorting for large datasets.
- Avoid excessive animations, unnecessary UI complexity, and inconsistent interaction patterns.
- Do not place technical stack traces or raw backend errors in end-user messages.

### Grid-based layouts and spacing

- Use CSS Grid or MUI Grid as the default for structured forms, dashboards, filters, and aligned groups of controls.
- Prefer a consistent 12-column desktop grid. Allow controls to span multiple columns based on their content and importance.
- Align related labels, inputs, and controls to shared grid boundaries rather than using arbitrary offsets.
- Adapt layouts responsively: single-column on narrow mobile screens, fewer columns on tablets, and the full grid when desktop space permits.
- Use Flexbox for simple one-dimensional groups, such as toolbars and button rows.
- Never use HTML tables solely to position form controls; reserve tables for tabular data.
- **Use MUI's 8px spacing system consistently**, through theme spacing tokens (for example, `theme.spacing(1)` for 8px, `theme.spacing(2)` for 16px, and `theme.spacing(3)` for 24px).
- Prefer theme spacing and shared layout components over one-off pixel values, manual positioning, or arbitrary margins. Exceptions are allowed for precise visual or accessibility needs and should be justified.
- Apply grid alignment and spacing consistently in modal forms and dedicated form pages.

### Tables as the default for record collections

- Prefer tables for displaying collections of records, administrative lists, search results, and other structured datasets.
- Use MUI tables or MUI X Data Grid as appropriate, with consistent columns, headers, sorting, filtering, and pagination where useful.
- Do not force inherently non-tabular content into tables. Use cards, timelines, trees, galleries, or other suitable components when they better express the content or interaction.
- Tables remain read-only for record management: creating and editing records must follow the modal-for-simple, page-for-complex rule.
- When a table has no records to display, show a reusable **no-records animation** centered both horizontally (X axis) and vertically (Y axis) within the table's available content area.
- Keep the empty-state animation and accompanying concise message together in the centered area. Optionally offer a relevant create or reset-filters action outside the animation or directly below its message.
- Distinguish an empty dataset from no search/filter matches, loading, and error states. Use appropriate messages for each and do not show the no-records animation during loading or on errors.
- Reserve a reasonable minimum height for the empty table body so the animation is visibly centered, even with zero rows. Keep table headers and toolbars in their normal positions.
- Respect reduced-motion accessibility preferences: provide a static fallback or disable animation when the user prefers reduced motion.

## 4. Numeric, currency, and date presentation

- Always right-align numeric values and currency amounts in UI text, data tables, summaries, reports, and read-only form displays.
- Right-align numeric and currency table headers with their corresponding values.
- For editable numeric and currency inputs, right-align the entered value while keeping descriptive labels readable.
- Use consistent decimal precision and locale-appropriate thousands separators; do not change stored numeric precision merely for display.
- Display all calendar dates in the exact `YYYY-MM-DD` format, for example `2020-10-18`.
- Use zero-padded months and days. Do not display ambiguous formats such as `10/18/2020`, `18/10/2020`, or `Oct 18, 2020`.
- Apply the date rule consistently in tables, forms, filters, detail pages, exports, and reports.
- Preserve proper date/time types and timezone handling internally; formatting is a presentation concern. If time must be shown, use `YYYY-MM-DD HH:mm` in 24-hour format unless a project explicitly specifies otherwise.

## Contextual help and plain-language explanations

- Design for users who may be unfamiliar with terminology or may not remember a process. Be respectful and never use condescending wording.
- Provide a contextual info icon and accessible tooltip or popover next to ambiguous labels, abbreviations, technical settings, business terminology, and non-obvious processes.
- Explain what the term means in plain language, what the user should do, and the practical effect of the choice when relevant.
- Include one brief concrete example when it materially improves understanding.
- Keep help concise and scannable. Use a help dialog or guided explanation for processes too complex for a short popover.
- Make contextual help available by click or tap and keyboard focus/activation; never rely on hover alone. Provide accessible names and appropriate focus behavior.
- Do not add info icons to obvious labels or overwhelm the interface with repetitive explanations.
- For potentially consequential settings, explain the outcome before the user commits the change.
- When introducing an unfamiliar term, proactively add contextual help rather than waiting for a request.

## 10. Additional UX and record-management standards

### 10.1 Prevent accidental data loss
- Track whether forms have unsaved changes. Before closing a dialog, navigating away, or refreshing a page, warn when changes would be lost.
- Do not warn when no changes exist. Respect browser navigation behavior and use a native before-unload warning when necessary.

### 10.2 Consistent feedback and notifications
- Use consistent MUI snackbar or alert patterns for success, failure, and relevant informational messages.
- Describe what happened and, for failures, how to recover. Never expose raw server errors or technical stack traces.
- Avoid redundant success notifications when the result is already unmistakable.

### 10.3 Required fields and validation
- Clearly identify required fields with a consistent indicator and accessible required state.
- Place specific validation messages next to the affected field and provide a summary or focus management when helpful.
- Validate on both client and server; preserve entered values when validation fails.

### 10.4 Standard table controls
- For tables where relevant, offer search, sorting, filtering, pagination, column visibility, and refresh.
- Keep controls and labels consistent across screens. Preserve search, filters, sorting, and pagination when opening a record and returning to the table, where practical.
- Use server-side search, sorting, and pagination for large datasets. Do not add controls that have no meaningful purpose.

### 10.5 Record activity history
- Provide an activity history for important records when accountability matters, including actor, action, timestamp, and relevant changes.
- Record audit events server-side. Restrict access to authorized roles and avoid storing secrets or unnecessary personal information in logs.
- Display timestamps in the configured timezone and use the established date formatting rules.

### 10.6 Loading and duplicate-action prevention
- Show clear loading feedback during asynchronous operations; use skeletons for structured content where useful.
- Disable or otherwise guard submit actions while saving. Also enforce idempotency or duplicate protection server-side for sensitive operations.
- Distinguish loading, empty, and error states; never display the no-records animation while loading or after a failed request.

### 10.7 Keyboard-friendly forms
- Ensure logical Tab order, visible focus indicators, keyboard-operable controls, and appropriate initial focus.
- Use Enter to submit only where expected and safe. Escape may dismiss a dialog only when it will not silently discard changes.
- Restore focus appropriately after dialogs close.

### 10.8 Soft deletion and archiving
- Prefer archiving or soft deletion for business-critical records where recovery, traceability, or retention is required.
- Provide restore functionality when appropriate. Keep deleted records out of ordinary views unless explicitly requested.
- Respect legal deletion obligations, data retention policies, and referential integrity. Do not apply soft deletion blindly to every entity.

### 10.9 Consistent form actions
- Position primary and secondary form actions consistently across dialogs and pages.
- Use specific labels such as `Create Record`, `Save Changes`, and `Cancel`, not vague `Submit` labels.
- Keep actions accessible and predictable across screen sizes.

### 10.10 Date and currency inputs
- Use date pickers or validated date inputs displaying `YYYY-MM-DD`.
- Use numeric inputs and suitable formatting for quantities, amounts, and currency. Right-align their visible numeric values.
- Define precision, rounding, separators, currency symbols, and locale rules explicitly. Store numeric data as appropriate numeric types, not formatted display strings.

### 10.11 Responsive tables
- On narrow screens, allow horizontal scrolling instead of compressing columns until unreadable.
- Preserve important columns or controls when practical, and keep actions reachable by touch and keyboard.
- Use cards instead of tables only when the content or user task clearly benefits from that format.

### 10.12 Accessibility by default
- Maintain adequate contrast, visible keyboard focus, meaningful labels, and accessible validation and status messages.
- Do not rely on color alone to convey meaning. Respect reduced-motion preferences, including for empty-state animations.
- Make popovers, dialogs, table controls, and notifications usable with assistive technologies.

## 11. Additional enterprise consistency rules

### 11.1 Consistent status badges
- Centralize status names, badge colors, and meanings. Use the same visual treatment for the same status throughout the application.
- Include readable status text so color is never the sole signal.

### 11.2 Server-side pagination
- Use server-side pagination, filtering, and sorting for large or growing datasets.
- Return total counts or pagination metadata when appropriate and prevent stale requests from replacing newer results.

### 11.3 Reusable confirmation dialogs
- Reuse a standard accessible confirmation-dialog component for delete, cancel, approve, and other consequential actions.
- Clearly state the target, consequence, and action. Distinguish reversible actions from permanent ones.

### 11.4 Filter and navigation persistence
- Preserve relevant search terms, filters, sorting, page index, and page size when navigating to a record and back.
- Reset pagination only when necessary, such as when a filter change invalidates the current page.

### 11.5 Timezone consistency
- Store instants in UTC and convert to the application's configured display timezone.
- Display dates as `YYYY-MM-DD` and date-times as `YYYY-MM-DD HH:mm` in 24-hour format unless a documented domain requirement calls for a different representation.
- Distinguish date-only values from timestamps; do not shift date-only values through timezone conversion.

### 11.6 No silent failures
- Handle failed operations explicitly. Show understandable, actionable feedback with retry options where appropriate.
- Log diagnostic details securely for developers while keeping user-facing messages safe and readable.
- Never falsely display success when an operation has failed or is still pending.

## 12. Additional navigation, data entry, and engineering standards

### Navigation and table interaction

- **Breadcrumb navigation:** On nested pages, show a clear breadcrumb trail reflecting the page hierarchy. Make ancestor links navigable and provide accessible labels. Avoid breadcrumbs on single-level pages where they add no value.
- **Double-click to view records:** Where records have a detail view, allow desktop users to double-click a data row to open it. Provide an explicit, keyboard-accessible View action for all users, including touch users. Do not use double-click to trigger editing or destructive operations. Avoid interfering with text selection or row controls.
- **Resizable table columns:** Where helpful for wide or variable-length data, support user-resizable columns. Keep sensible minimum and maximum widths, preserve readable headers, and persist preferences when appropriate. Do not require this feature for simple tables.
- **One-click copy:** Provide clearly labeled copy actions for frequently reused identifiers, references, email addresses, and similar values. Give brief success or failure feedback. Do not expose sensitive values without appropriate authorization.
- **Active filter indicators:** Clearly show which filters are active, display an active-filter count when helpful, and provide an obvious Clear Filters action. Preserve useful filter state when navigating between list and detail views.

### Forms and data integrity

- **Complex form sections:** Organize long forms into labeled sections or tabs, with consistent grid alignment. Use a step-by-step wizard only when the workflow genuinely requires a sequence. Preserve values when switching sections.
- **Duplicate record prevention:** Check for likely duplicates when unique identifiers are entered, and enforce actual uniqueness with database constraints. Handle concurrent submissions and uniqueness violations with understandable errors. Do not assume frontend duplicate checks are sufficient.
- **Form draft recovery:** For lengthy forms, provide draft saving or recovery when useful and appropriate. Inform users when a draft is saved and allow them to discard it. Do not store credentials, payment secrets, or other sensitive form content in insecure browser storage. Account for expiry and access control.
- **Automatic calculations:** Automatically update derived values such as subtotals, discounts, totals, and balances when relevant. Show the inputs and calculation results clearly. Make derived fields read-only unless authorized overrides are part of the requirements. Recalculate and validate authoritative values on the backend; use suitable decimal arithmetic for money.
- **Explain disabled actions:** When a control is disabled, explain why and how to resolve the condition, using nearby helper text or an accessible wrapper/popover. Do not rely on hover alone or on tooltips attached directly to disabled controls.

### Architecture, performance, and agent discipline

- **Reusable UI components:** Prefer shared, configurable components for common tables, dialogs, form fields, confirmation prompts, empty states, and status indicators. Avoid premature abstraction and do not build nearly identical components for each page.
- **Standardized API errors:** Use a consistent Django Ninja error response shape with stable machine-readable codes, human-readable messages, and field-level details where applicable. Use appropriate HTTP status codes. Log diagnostic context server-side without exposing stack traces or secrets to end users.
- **Database migration safety:** Manage schema changes through version-controlled Django migrations. Review destructive and irreversible operations, protect existing data, plan backfills and rollbacks when practical, and never reset or silently drop production data. Require explicit approval before destructive production migrations.
- **Performance standards:** Prefer server-side pagination, filtering, and sorting for large datasets. Debounce user-driven searches, avoid unnecessary requests and renders, prevent N+1 queries, and add indexes based on observed query patterns. Measure before optimizing and preserve correctness.
- **Codex change discipline:** Before editing, inspect relevant files, architecture, conventions, and tests. Make focused changes that preserve working behavior. After editing, report changed files, behavior changes, checks actually run and their outcomes, and any remaining risks or unverified work. Never claim a test passed unless it was executed successfully.

## Additional interaction and productivity standards

- **Keyboard shortcuts:** Support familiar shortcuts where appropriate, including `Ctrl+S` or `Cmd+S` to save, `/` to focus search, and `Escape` to close dialogs when safe. Do not override standard browser shortcuts. Make shortcuts discoverable and avoid triggering them while typing in unrelated controls.
- **Undo reversible actions:** Offer an Undo action for suitable reversible changes. Clearly distinguish undoable changes from permanent operations. Never promise Undo unless the operation can actually be reversed.
- **Saved table views:** For complex, frequently used tables, let users save and restore filters, sorting, visible columns, and column widths. Scope saved views to the appropriate user and permissions. Do not force saved views into simple tables.
- **Data export:** Where useful, support CSV and/or Excel export of authorized records. Respect filters, permissions, and data minimization. Clearly state whether the export includes the current page, selected rows, or all matching records. Generate large exports server-side when appropriate.
- **Connection-loss handling:** Provide understandable offline/network-failure feedback and safe retry controls. Preserve unsaved work where practical without storing sensitive content insecurely. Do not claim an operation succeeded until the server confirms it.
- **Concurrent editing protection:** For records commonly edited by multiple users, use optimistic concurrency control (such as a version number or conditional update). Detect conflicts and offer a clear resolution path rather than silently overwriting someone else's changes.
- **Idempotent critical operations:** Protect payments, orders, and other critical state-changing requests from duplicate execution with server-side idempotency keys, uniqueness constraints, or equivalent controls. A disabled submit button alone is insufficient.
- **Session expiration handling:** Renew sessions securely where appropriate. When reauthentication is required, explain the situation and preserve safe, non-sensitive work if feasible. Never expose credentials or tokens in UI messages or browser storage unnecessarily.
- **Centralized design tokens:** Define typography, colors, spacing, border radii, density, component sizing, and breakpoints in the MUI theme. Avoid scattered hardcoded styling values. Keep the established 8px spacing scale.
- **Centralized UI text:** Keep repeated labels, validation messages, and notifications in shared resources/constants to maintain consistent wording and enable later localization. Avoid unnecessary abstraction for one-off text.
