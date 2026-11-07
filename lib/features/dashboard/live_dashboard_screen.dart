import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/formatting.dart';

final dashboardSessionProvider = StreamProvider<Session?>((ref) async* {
  if (!AppConfig.hasSupabase) {
    yield null;
    return;
  }
  final auth = Supabase.instance.client.auth;
  yield auth.currentSession;
  await for (final event in auth.onAuthStateChange) {
    yield event.session;
  }
});

final liveDashboardProvider = FutureProvider<_DashboardData>((ref) async {
  if (!AppConfig.hasSupabase) {
    return const _DashboardData();
  }
  final session = await ref.watch(dashboardSessionProvider.future);
  if (session == null) return const _DashboardData();
  final client = Supabase.instance.client;
  final responses = await Future.wait<dynamic>([
    client.from('loans').select('id,status').eq('is_personal', false),
    client
        .from('payments')
        .select(
          'amount_centavos,received_at,method,status,loan:loans!inner(is_personal,borrower:borrowers(first_name,last_name))',
        )
        .eq('loan.is_personal', false)
        .order('received_at', ascending: false),
    client
        .from('installments')
        .select(
          'id,loan_id,due_date,scheduled_centavos,loan:loans!inner(status,is_personal,borrower:borrowers(first_name,last_name))',
        )
        .eq('loan.is_personal', false),
    client
        .from('payment_allocations')
        .select(
          'installment_id,principal_centavos,interest_centavos,penalty_centavos,payment:payments!inner(status)',
        )
        .eq('payment.status', 'verified'),
    client.rpc('organization_dashboard_summary'),
  ]);
  return _DashboardData.fromRows(
    List<Map<String, dynamic>>.from(responses[0]),
    List<Map<String, dynamic>>.from(responses[1]),
    List<Map<String, dynamic>>.from(responses[2]),
    List<Map<String, dynamic>>.from(responses[3]),
    Map<String, dynamic>.from(responses[4] as Map),
  );
});

class _DashboardData {
  const _DashboardData({
    this.outstanding = 0,
    this.collected = 0,
    this.dueToday = 0,
    this.overdue = 0,
    this.activeLoans = 0,
    this.overdueCount = 0,
    this.dueTodayCount = 0,
    this.due = const [],
    this.payments = const [],
  });
  final int outstanding,
      collected,
      dueToday,
      overdue,
      activeLoans,
      overdueCount,
      dueTodayCount;
  final List<_DueItem> due;
  final List<_PaymentItem> payments;

  factory _DashboardData.fromRows(
    List<Map<String, dynamic>> loans,
    List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> installments,
    List<Map<String, dynamic>> allocations,
    Map<String, dynamic> summary,
  ) {
    final now = DateTime.now();
    final today = _date(now);
    final paid = <String, int>{};
    for (final row in allocations) {
      final id = row['installment_id'] as String;
      paid[id] =
          (paid[id] ?? 0) +
          (row['principal_centavos'] as int) +
          (row['interest_centavos'] as int) +
          (row['penalty_centavos'] as int);
    }
    final due = <_DueItem>[];
    for (final row in installments) {
      final loan = Map<String, dynamic>.from(row['loan'] as Map);
      if (loan['status'] != 'active') continue;
      final balance =
          ((row['scheduled_centavos'] as int) - (paid[row['id']] ?? 0)).clamp(
            0,
            1 << 62,
          );
      if (balance == 0) continue;
      final dueDate = row['due_date'] as String;
      final borrower = Map<String, dynamic>.from(loan['borrower'] as Map);
      if (dueDate == today) {
        due.add(
          _DueItem(
            '${borrower['last_name']}, ${borrower['first_name']}',
            balance,
          ),
        );
      }
    }
    var collected = 0;
    final recent = <_PaymentItem>[];
    for (final row in payments.where((item) => item['status'] == 'verified')) {
      final received = DateTime.parse(row['received_at'] as String).toLocal();
      if (received.year == now.year && received.month == now.month) {
        collected += row['amount_centavos'] as int;
      }
      if (recent.length < 3) {
        final loan = Map<String, dynamic>.from(row['loan'] as Map);
        final borrower = Map<String, dynamic>.from(loan['borrower'] as Map);
        recent.add(
          _PaymentItem(
            '${borrower['last_name']}, ${borrower['first_name']}',
            row['amount_centavos'] as int,
            received,
            row['method'] as String,
          ),
        );
      }
    }
    return _DashboardData(
      outstanding: summary['outstanding'] as int,
      collected: collected,
      dueToday: summary['due_today'] as int,
      overdue: summary['overdue'] as int,
      activeLoans: loans.where((row) => row['status'] == 'active').length,
      overdueCount: summary['overdue_count'] as int,
      dueTodayCount: summary['due_today_count'] as int,
      due: due.take(3).toList(),
      payments: recent,
    );
  }
}

class _DueItem {
  const _DueItem(this.name, this.amount);
  final String name;
  final int amount;
}

class _PaymentItem {
  const _PaymentItem(this.name, this.amount, this.receivedAt, this.method);
  final String name, method;
  final int amount;
  final DateTime receivedAt;
}

class LiveDashboardScreen extends ConsumerWidget {
  const LiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(liveDashboardProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(liveDashboardProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry dashboard'),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.refresh(liveDashboardProvider.future),
          child: LayoutBuilder(
            builder: (context, box) {
              final mobile = box.maxWidth < 700;
              return ListView(
                padding: EdgeInsets.all(mobile ? 14 : 16),
                children: [
                  _hero(context),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: mobile ? 2 : 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                    childAspectRatio: mobile ? 1.0 : 1.55,
                    children: [
                      _kpi(
                        context,
                        'Outstanding Loans',
                        data.outstanding,
                        '${data.activeLoans} active loans',
                        Icons.account_balance_wallet_outlined,
                      ),
                      _kpi(
                        context,
                        'Collections This Month',
                        data.collected,
                        'Verified payments',
                        Icons.savings_outlined,
                      ),
                      _kpi(
                        context,
                        'Due Today',
                        data.dueToday,
                        '${data.dueTodayCount} installments',
                        Icons.event_outlined,
                      ),
                      _kpi(
                        context,
                        'Overdue',
                        data.overdue,
                        '${data.overdueCount} installments',
                        Icons.warning_amber_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (mobile) ...[
                    _dueCard(context, data),
                    const SizedBox(height: 10),
                    _paymentsCard(context, data),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _paymentsCard(context, data)),
                        const SizedBox(width: 10),
                        Expanded(child: _dueCard(context, data)),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _action(
                        'New Loan',
                        Icons.add,
                        () => context.go('/loans/new'),
                      ),
                      _action(
                        'Record Payment',
                        Icons.credit_card_outlined,
                        () => context.go('/payments'),
                      ),
                      _action(
                        'Collections',
                        Icons.event_note_outlined,
                        () => context.go('/collections'),
                      ),
                      _action(
                        'Reports',
                        Icons.bar_chart_outlined,
                        () => context.go('/reports'),
                      ),
                      _action(
                        'Documents',
                        Icons.description_outlined,
                        () => context.go('/documents'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );

  Widget _hero(BuildContext context) => Container(
    height: MediaQuery.sizeOf(context).width < 700 ? 122 : 106,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .24),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.lerp(
                Theme.of(context).colorScheme.primary,
                Colors.white,
                .22,
              ) ??
              Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.primary,
          Color.lerp(
                Theme.of(context).colorScheme.primary,
                Colors.black,
                .42,
              ) ??
              Theme.of(context).colorScheme.primary,
        ],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _LiveHeroBackdropPainter()),
        Positioned(
          right: 4,
          top: -8,
          bottom: -14,
          child: IgnorePointer(
            child: Image.asset(
              'assets/branding/dashboard_duck.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 120),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good day!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      color: Color(0x33000000),
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 4),
              Text(
                "Here's your live lending business overview.",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _kpi(
    BuildContext context,
    String label,
    int amount,
    String note,
    IconData icon,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          FittedBox(
            child: Text(
              formatPeso(amount),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dueCard(BuildContext context, _DashboardData data) => _listCard(
    context,
    "Today's Collections",
    data.due.isEmpty
        ? [const ListTile(title: Text('No collections are due today.'))]
        : [
            for (final item in data.due)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text(formatPeso(item.amount)),
              ),
          ],
  );

  Widget _paymentsCard(BuildContext context, _DashboardData data) => _listCard(
    context,
    'Recent Payments',
    data.payments.isEmpty
        ? [const ListTile(title: Text('No verified payments yet.'))]
        : [
            for (final item in data.payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${formatPhilippineDateTime(item.receivedAt)} · ${item.method}',
                ),
                trailing: Text(formatPeso(item.amount)),
              ),
          ],
  );

  Widget _listCard(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        ),
      );

  Widget _action(String label, IconData icon, VoidCallback onPressed) =>
      SizedBox(
        width: 150,
        height: 54,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}

class _LiveHeroBackdropPainter extends CustomPainter {
  const _LiveHeroBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * .82, size.height * .28),
      size.height * .82,
      Paint()..color = const Color(0x10FFFFFF),
    );
    canvas.drawCircle(
      Offset(size.width * .58, size.height * 1.15),
      size.height * .95,
      Paint()..color = const Color(0x10FFFFFF),
    );
    final wave = Path()
      ..moveTo(size.width * .52, size.height)
      ..cubicTo(
        size.width * .68,
        size.height * .35,
        size.width * .80,
        size.height * 1.25,
        size.width,
        size.height * .35,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(wave, Paint()..color = const Color(0x1624B8FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
