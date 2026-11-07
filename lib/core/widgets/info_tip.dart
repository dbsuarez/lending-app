import 'package:flutter/material.dart';

/// Plain-language explanations of lending terms used in the app.
/// Keep these short, concrete, and free of jargon.
const glossary = <String, ({String title, String body})>{
  'principal': (
    title: 'Principal',
    body:
        'The amount you actually lent: the money that left your hands. '
        'Interest is calculated from it.',
  ),
  'flat_interest': (
    title: 'Flat interest',
    body:
        'Interest charged on the original amount lent, for every month of '
        'the loan, even while it is being paid down. Example: ₱10,000 at 5% '
        'a month for 3 months = ₱1,500 interest.',
  ),
  'monthly_rate': (
    title: 'Monthly rate',
    body: 'The percentage of the principal charged as interest each month.',
  ),
  'total_repayable': (
    title: 'Total repayable',
    body: 'Principal plus all the interest: what the borrower pays in total.',
  ),
  'still_owed': (
    title: 'Still owed (balance)',
    body:
        'Total repayable minus verified payments. Payments still waiting '
        'for verification are not subtracted yet.',
  ),
  'installment': (
    title: 'Installment',
    body:
        'One scheduled payment. A loan is split into equal installments, '
        'usually one per payday.',
  ),
  'payment_progress': (
    title: 'Payment progress',
    body: 'How much of the total repayable has been paid, as a percentage.',
  ),
  'term': (
    title: 'Term',
    body: 'How many months the borrower has to pay the loan back.',
  ),
  'borrowed': (
    title: 'Borrowed date',
    body:
        'The day the money was released to the borrower (the disbursement '
        'date). Drafts have none yet.',
  ),
  'paid_date': (
    title: 'Paid date',
    body: 'The date of the last verified payment that fully paid the loan.',
  ),
  'disburse': (
    title: 'Confirm & Disburse',
    body:
        'Records that you released the money to the borrower. The loan '
        'becomes Active, the schedule starts, and the terms are locked. '
        '"Disburse" just means "release the money".',
  ),
  'draft': (
    title: 'Draft',
    body:
        'A loan being set up. No money has been released and the borrower '
        'owes nothing yet. You can still cancel it.',
  ),
  'amend_due_date': (
    title: 'Amend Due Date',
    body:
        '"Amend" means "change". This moves one unpaid installment to a new '
        'date, for example when the borrower asks to pay a few days later. '
        'The amount stays the same; only the date moves. You record why, and '
        'the date the borrower agreed. Installments that are already paid '
        'cannot be moved, and dates must stay in order.',
  ),
  'consent_date': (
    title: 'Borrower consent date',
    body:
        'The date the borrower agreed to the change. Keep proof (a text '
        'message or signed note) in case of a dispute.',
  ),
  'refinance': (
    title: 'Refinance',
    body:
        'Replace this loan with a new one with new terms (amount, rate, or '
        'months). The current loan is closed as "Refinanced" and a new draft '
        'loan is created and linked to it. Nothing is paid out until you '
        'confirm the new loan.',
  ),
  'early_payoff': (
    title: 'Early Payoff',
    body:
        'The borrower pays everything at once before the end of the term. '
        'They pay the remaining principal plus interest only for '
        'installments already due. Interest for future months is waived '
        '(not charged).',
  ),
  'mark_personal': (
    title: 'Personal loan',
    body:
        'A loan from your own pocket, not the business. Personal loans are '
        'kept separate and do not count in the dashboard, collections, '
        'payments, or reports.',
  ),
  'cancel_draft': (
    title: 'Cancel Draft',
    body:
        'Stops a loan that was never released. Nothing is owed. The draft '
        'stays in the history as Cancelled with your reason.',
  ),
  'pending_verification': (
    title: 'Pending verification',
    body:
        'A payment was recorded but not yet confirmed as received, for '
        'example a GCash or bank transfer whose reference you still need to '
        'check. It does not reduce the balance until it is verified.',
  ),
  'verify': (
    title: 'Verify',
    body:
        'Confirms the money really arrived. It is then applied to the oldest '
        'unpaid installments: interest first, then principal. Cash payments '
        'are verified automatically.',
  ),
  'reject': (
    title: 'Reject',
    body:
        'For a recorded payment that never arrived or was wrong. It stops '
        'counting, and the reason is kept in the audit history.',
  ),
  'reverse': (
    title: 'Reverse',
    body:
        'Takes back a payment that was already verified, for example a '
        'bounced transfer or a duplicate. The balance goes back up. Use Undo '
        'instead if you just made a mistake.',
  ),
  'aging': (
    title: 'Aging',
    body:
        'Groups unpaid amounts by how long they have been overdue, so you '
        'can see which borrowers are furthest behind.',
  ),
  'unapplied_credit': (
    title: 'Unapplied credit',
    body:
        'Money paid beyond what was due (an overpayment) that has not been '
        'applied to any installment yet.',
  ),
  'contractual_total': (
    title: 'Contractual total',
    body: 'The total repayable of all active loans, as agreed in their terms.',
  ),
  'audit_history': (
    title: 'Audit history',
    body:
        'A permanent log of who did what and when. Entries cannot be edited '
        'or deleted, which protects you if a record is ever questioned.',
  ),
  'customer_link': (
    title: 'Customer status link',
    body:
        'A private web page you can send the borrower so they can see their '
        'schedule and payments. It is read-only and works until you revoke '
        'it.',
  ),
  'extension_preview': (
    title: 'Extension preview',
    body:
        'Shows what an overdue borrower would owe if you charged interest '
        'for the extra time past the final due date. It is only a '
        'calculation: nothing is saved or changed.',
  ),
  'cutoff': (
    title: 'Payday cutoff',
    body:
        'The borrower\'s payday dates (for example the 15th and 30th). '
        'Counting by cutoffs charges whole pay periods, which is how many '
        'borrowers plan to pay.',
  ),
  'extension_base': (
    title: 'Interest charged on',
    body:
        'Unpaid principal charges the monthly rate only on what the '
        'borrower still owes from the money lent; fairer when part was '
        'already paid. Original principal charges it on the full amount '
        'lent, the same way the loan\'s own flat interest works.',
  ),
};

/// Small ⓘ icon: hover shows the explanation, tap opens it in a dialog
/// (tap works on phones, where there is no hover).
class InfoTip extends StatelessWidget {
  const InfoTip(this.term, {super.key, this.size = 18});
  final String term;
  final double size;

  @override
  Widget build(BuildContext context) {
    final entry = glossary[term];
    if (entry == null) return const SizedBox.shrink();
    return Tooltip(
      message: entry.body,
      waitDuration: const Duration(milliseconds: 300),
      child: InkResponse(
        radius: 18,
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(entry.title),
            content: Text(entry.body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.info_outline,
            size: size,
            semanticLabel: 'What is ${entry.title}?',
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// A title with an ⓘ explanation next to it, for dialogs and sections.
class TitleWithInfo extends StatelessWidget {
  const TitleWithInfo(this.title, this.term, {super.key, this.style});
  final String title, term;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(title, style: style)),
      const SizedBox(width: 4),
      InfoTip(term),
    ],
  );
}
