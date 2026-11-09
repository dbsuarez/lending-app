# What's new and what to check (2026-11-08 to 2026-11-09)

Tick each item after you try it. Everything is live on the website. The phone
app was last installed at build 20261109_1110, so newer items marked *(web)*
reach the phone only after the next install.

## Do these first

- [x] Open the website and refresh once. If it reloads by itself, that is
      the old-files cleanup. All icons should show, including the columns
      button at the top-right of tables.
- [x] Turn on the weekly automatic backup. Run this once on this PC:
      `powershell -ExecutionPolicy Bypass -File tool/backup/schedule_weekly.ps1`
- [x] Send the [legal review doc](https://claude.ai/artifact/VioPrupv8pLNndXwZgbWnN)
      to your lawyer. Share it from the page first; only you can open it now.

## Loans

- [x] **Edit Draft**: open a draft, then Edit Draft. The form opens filled in,
      and the last step shows Before → After.
- [x] **Correct Loan**: on a released loan with no payments, use Correct
      (desktop) or Actions (phone). A reason is required, and Undo appears
      after saving.
- [x] **Edit Money Release**: change the release date, method or reference
      (reason required).
- [x] **Copy button** beside the loan number at the top of a loan.
- [x] **Undo Early Payoff** only appears on loans that were paid off early.
- [x] **Early Payoff** *(web)*: the window lists three rules with their
      amounts: waive future interest, this month's interest (preselected),
      or all remaining interest. Change the date and all three amounts update.
- [x] The loan page buttons sit on their own row and the loan number no longer
      squeezes.

## Payments

- [ ] **Record payment with a date**: pick the date the money came in.
- [ ] **Late reason**: record a payment after its due date. The window
      says how many days late it is and asks why (quick picks or your own
      words). The reason shows as a clock icon in Payments and as "Late: …"
      on the loan's Payments tab.
- [x] **Edit payment**: the pencil or Edit changes the date, method,
      reference or late reason.
- [x] **Receipt**: on a verified payment, click Receipt to get a PDF receipt.
- [x] After any payment change, the Ongoing tag, Collections, Dashboard and
      aging report update without a hard refresh.

## Evidence (loan page → Documents tab)

- [x] Upload a photo or PDF. You choose a category first.
- [x] Files are grouped by category. The new category is **Late-payment
      reason / promise**; Kristoper's and Darenden's screenshots are in it.
- [x] Open a file inside the app: zoom photos, scroll PDFs, Save a copy,
      Change category.
- [x] A 📎 count shows beside loans that have evidence (Loans list,
      Documents page, Documents tab).

## PDFs (loan page → Documents tab, or the print menu)

- [x] Every PDF shows your business name and contacts at the top.
- [x] **Statement of account**: amount due now, overdue days, only the unpaid
      installments, payments received, and how to pay.
- [x] **Loan agreement**: disclosure, terms and schedule, with no draft note.
      The early-payment clause now says "at least the month's interest".
- [x] **Acknowledgment of release**: the borrower signs that they received the
      money. Imported loans show no "IT Avenue.xlsx" note.
- [x] **Payment receipt** (A5), from Payments → Receipt.

## Customer status link (loan → Customer link → open it)

- [X] Red **Amount due now** banner when overdue; otherwise "Next payment …".
- [x] Schedule shows still owed per installment, and Overdue / Due today /
      Upcoming.
- [x] **Loan Terms** tab with no payoff amount (removed as you asked).
- [x] Payment history with receipt numbers, the last 4 digits of references,
      and **View receipt** (print or save as PDF).
- [x] Your phone and email at the bottom.

## Penalties *(web)*

- [x] Settings → **Default penalties**: choose None, Fixed amount, Percentage of
      overdue or Manual, and the grace days (default 3). New loans start with it.
- [x] New loan: the Terms step shows **Penalties** with **Change** (per loan,
      while it is a draft). Existing loans stay "None" and are never charged.
- [x] A loan with fixed/percentage penalties: once an installment is unpaid past
      the grace days, a penalty appears, and again at every payday cutoff while
      it stays unpaid. See the loan's Overview → **Penalties** card and the
      **Penalty** column on Schedule.
- [ ] **Waive** a penalty (reason required). A paid penalty cannot be waived.
- [ ] Manual (or any loan with penalties): **Add penalty** on the card.
- [ ] Payments pay **penalty → interest → principal** on the oldest installment.
- [ ] The agreement PDF and the customer page show that loan's penalty terms.

## Settings

- [x] **Back up everything**: one checked file, with uploaded files included.
- [x] **Check a backup**: open a backup file. It checks it and compares it
      with the live data.
- [x] **Restore a loan from a backup**: pick a backup, choose a loan,
      preview, give a reason, then Restore. Undo is available right after.
- [x] Every window opened from Settings has a **Back** arrow; so does
      Audit history.
- [x] Long-press a list filter to make it the default (works on the phone).
- [x] Exports on the phone open a "Save to…" screen, so you choose the folder.
- [x] **Update prompt**: when a newer version is out, a bar asks you to
      update, about 10 seconds after opening the app.

## How to back up a loan

Backups always cover the **whole business** (every loan, payment and file),
not single loans. That way one file restores everything consistently.

- **Make one now:** Settings → Back up everything. The file goes to Downloads
  (computer) or the folder you choose (phone).
- **Automatic:** the weekly backup (see "Do these first"). It keeps 12 copies
  in `backups/` and a second copy on drive E:.
- **Undo damage to one loan:** Settings → Restore a loan from a backup → pick
  the backup → pick the loan → preview → Restore. Only that loan changes.

Tip: before trying something risky on a real loan, make a backup first. Then
you can put that one loan back afterwards.

## Still to come

- Correct Terms for loans that already have payments.
- Legal review, then final agreement wording.
