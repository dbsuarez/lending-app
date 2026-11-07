import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/formatting.dart';
import '../../data/repositories/shared_loan_repository.dart';
import '../../domain/models/models.dart';

class SharedLoanStatusScreen extends StatefulWidget {
  const SharedLoanStatusScreen({super.key, required this.token});
  final String token;

  @override
  State<SharedLoanStatusScreen> createState() => _SharedLoanStatusScreenState();
}

class _SharedLoanStatusScreenState extends State<SharedLoanStatusScreen> {
  late Future<SharedLoanStatus> status = _load();

  Future<SharedLoanStatus> _load() =>
      SharedLoanRepository(Supabase.instance.client).fetch(widget.token);

  void _refresh() => setState(() => status = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: FutureBuilder<SharedLoanStatus>(
        future: status,
        builder: (_, snapshot) =>
            Text(snapshot.data?.businessName ?? 'Loan Status'),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh loan status',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<SharedLoanStatus>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_off, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'This loan-status link is invalid or has been revoked.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return _content(snapshot.data!);
      },
    ),
  );

  Widget _content(SharedLoanStatus loan) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Hello, ${loan.borrower}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${loan.loanReference} · ${_statusLabel(loan.loanStatus)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Metric('Total repayable', loan.totalCentavos),
                        _Metric('Verified payments', loan.verifiedPaidCentavos),
                        _Metric('Pending verification', loan.pendingCentavos),
                        _Metric('Current balance', loan.outstandingCentavos),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const TabBar(
                      tabs: [
                        Tab(text: 'Payment Schedule'),
                        Tab(text: 'Payment History'),
                      ],
                    ),
                    SizedBox(
                      height: 440,
                      child: TabBarView(
                        children: [
                          _SharedSchedule(items: loan.schedule),
                          _SharedPayments(items: loan.payments),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This read-only page remains available until the lender revokes its link. Contact the lender if a payment or balance appears incorrect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    height: 92,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label),
            const Spacer(),
            Text(
              formatPeso(value),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SharedSchedule extends StatelessWidget {
  const _SharedSchedule({required this.items});
  final List<SharedScheduleItem> items;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.symmetric(vertical: 12),
    itemCount: items.length,
    separatorBuilder: (_, _) => const SizedBox(height: 6),
    itemBuilder: (_, index) {
      final item = items[index];
      return Card(
        child: ListTile(
          leading: CircleAvatar(child: Text('${item.sequence}')),
          title: Text(formatPhilippineDate(item.dueDate)),
          subtitle: Text(_statusLabel(item.status)),
          trailing: Text(
            formatPeso(item.scheduledCentavos),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    },
  );
}

class _SharedPayments extends StatelessWidget {
  const _SharedPayments({required this.items});
  final List<SharedPaymentItem> items;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('No payment records to display yet.'))
      : ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (_, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                title: Text(
                  formatPhilippineDateTime(item.receivedAt.toLocal()),
                ),
                subtitle: Text('${item.method} · ${_statusLabel(item.status)}'),
                trailing: Text(
                  formatPeso(item.amountCentavos),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          },
        );
}

String _statusLabel(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
