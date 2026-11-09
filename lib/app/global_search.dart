import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatting.dart';
import '../domain/models/models.dart';
import '../features/borrowers/borrowers_controller.dart';
import '../features/loans/loans_controller.dart';
import '../features/payments/payments_controller.dart';

class SearchHit {
  const SearchHit(this.group, this.icon, this.title, this.subtitle, this.route);
  final String group, title, subtitle, route;
  final IconData icon;
}

String _ref(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';
String _receipt(String id) => 'PR-${id.substring(0, 8).toUpperCase()}';
String _squash(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s\-.,₱]'), '');

/// Matches the query against borrowers (name, phone), loans (reference,
/// borrower) and payments (reference, receipt number, amount).
List<SearchHit> searchEverything({
  required String query,
  required List<Borrower> borrowers,
  required List<LoanSummary> loans,
  required List<PaymentSummary> payments,
  int perGroup = 6,
}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final squashed = _squash(q);
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  // "2875", "2,875", "2875.00" -> 287500 centavos.
  final amount = double.tryParse(q.replaceAll(RegExp(r'[,₱\s]'), ''));
  final amountCentavos = amount == null ? null : (amount * 100).round();

  bool nameMatches(String name) =>
      name.toLowerCase().contains(q) ||
      q.split(RegExp(r'\s+')).every((w) => name.toLowerCase().contains(w));

  final hits = <SearchHit>[];
  final borrowerHits = [
    for (final b in borrowers)
      if (nameMatches('${b.firstName} ${b.lastName}') ||
          (digits.length >= 3 &&
              b.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
        SearchHit(
          'Borrowers',
          Icons.person_outline,
          b.displayName,
          b.phone.isEmpty ? 'Borrower' : b.phone,
          '/borrowers/${b.id}',
        ),
  ];
  hits.addAll(borrowerHits.take(perGroup));

  final loanHits = [
    for (final l in loans)
      if (_squash(_ref(l.id)).contains(squashed.replaceFirst('ln', '')) ||
          nameMatches(l.borrowerName))
        SearchHit(
          'Loans',
          Icons.handshake_outlined,
          '${_ref(l.id)} · ${l.borrowerName}',
          '${_status(l.status)} · ${formatPeso(l.totalCentavos)}',
          '/loans/${l.id}?from=${l.isPersonal ? 'personal' : 'loans'}',
        ),
  ];
  hits.addAll(loanHits.take(perGroup));

  final paymentHits = [
    for (final p in payments)
      if ((p.reference.isNotEmpty && _squash(p.reference).contains(squashed)) ||
          _squash(_receipt(p.id)).contains(squashed.replaceFirst('pr', '')) &&
              squashed.length >= 4 ||
          (amountCentavos != null && p.amountCentavos == amountCentavos))
        SearchHit(
          'Payments',
          Icons.payments_outlined,
          '${formatPeso(p.amountCentavos)} · ${p.borrowerName}',
          '${formatPhilippineDate(p.receivedAt)} · ${p.method}'
              '${p.reference.isEmpty ? '' : ' · ${p.reference}'}'
              ' · ${_status(p.status)}',
          '/loans/${p.loanId}?from=loans',
        ),
  ];
  hits.addAll(paymentHits.take(perGroup));
  return hits;
}

String _status(String s) => switch (s) {
  'fully_paid' => 'Paid',
  'pending' => 'Pending',
  'verified' => 'Verified',
  'reversed' => 'Reversed',
  'rejected' => 'Rejected',
  _ => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1),
};

/// The top bar search. [compact] shows a search icon (phones) that opens a
/// full-screen search; otherwise a short search box (computers), focused
/// with the "/" key.
class GlobalSearch extends ConsumerStatefulWidget {
  const GlobalSearch({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends ConsumerState<GlobalSearch> {
  final controller = SearchController();

  @override
  void initState() {
    super.initState();
    if (!widget.compact) HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (!widget.compact) HardwareKeyboard.instance.removeHandler(_onKey);
    controller.dispose();
    super.dispose();
  }

  /// "/" opens the search unless the user is typing in a field.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.slash ||
        controller.isOpen) {
      return false;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    controller.openView();
    return true;
  }

  Future<Iterable<Widget>> _suggestions(
    BuildContext context,
    SearchController search,
  ) async {
    final query = search.text;
    final theme = Theme.of(context);
    if (query.trim().length < 2) {
      return [
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Type a name, loan number, phone, amount or reference'),
          subtitle: Text('e.g. Maria · LN-6B98 · 0917 · 2875 · PR-4DD3'),
        ),
      ];
    }
    List<T> safe<T>(List<T>? list) => list ?? <T>[];
    final results = await Future.wait([
      ref
          .read(borrowersControllerProvider.future)
          .then<Object>((v) => v)
          .catchError((_) => <Borrower>[]),
      ref
          .read(loansControllerProvider.future)
          .then<Object>((v) => v)
          .catchError((_) => <LoanSummary>[]),
      ref
          .read(paymentsControllerProvider.future)
          .then<Object>((v) => v)
          .catchError((_) => <PaymentSummary>[]),
    ]);
    final hits = searchEverything(
      query: query,
      borrowers: safe(results[0] as List<Borrower>?),
      loans: safe(results[1] as List<LoanSummary>?),
      payments: safe(results[2] as List<PaymentSummary>?),
    );
    if (hits.isEmpty) {
      return [ListTile(title: Text('Nothing matches “${query.trim()}”.'))];
    }
    final tiles = <Widget>[];
    String? group;
    for (final hit in hits) {
      if (hit.group != group) {
        group = hit.group;
        tiles.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(hit.group, style: theme.textTheme.labelLarge),
          ),
        );
      }
      tiles.add(
        ListTile(
          leading: Icon(hit.icon),
          title: Text(hit.title),
          subtitle: Text(hit.subtitle),
          onTap: () {
            search.closeView('');
            if (mounted) this.context.go(hit.route);
          },
        ),
      );
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) => SearchAnchor(
    searchController: controller,
    isFullScreen: widget.compact,
    viewHintText: 'Search borrowers, loans, payments…',
    suggestionsBuilder: _suggestions,
    builder: (context, search) => widget.compact
        ? IconButton(
            tooltip: 'Search',
            onPressed: search.openView,
            icon: const Icon(Icons.search),
          )
        : SearchBar(
            controller: search,
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12),
            ),
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.bodyMedium,
            ),
            hintStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            hintText: 'Search borrower, loan, payment or reference  ( / )',
            leading: const Icon(Icons.search, size: 20),
            onTap: search.openView,
            onChanged: (_) => search.openView(),
          ),
  );
}
