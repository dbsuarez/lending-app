import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/formatting.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final compact = c.maxWidth < 700;
      return SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2B68E9), Color(0xFF1547B4)],
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good evening!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Here’s your local demo lending overview.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: compact ? 2 : 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: compact ? 1.05 : 1.2,
              children: [
                const _Kpi(
                  'Outstanding balance',
                  124800000,
                  Icons.account_balance_wallet_outlined,
                  AppColors.blue600,
                  '14 active demo loans',
                ),
                const _Kpi(
                  'Collected this month',
                  31260000,
                  Icons.savings_outlined,
                  AppColors.success,
                  'Fixture data',
                ),
                const _Kpi(
                  'Due today',
                  5200000,
                  Icons.event_outlined,
                  AppColors.violet600,
                  '20 installments',
                ),
                const _Kpi(
                  'Overdue',
                  18640000,
                  Icons.warning_amber_rounded,
                  AppColors.danger,
                  '37 installments',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (compact) ...[
              const _Collections(),
              const SizedBox(height: 16),
              const _Trend(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 3, child: _Trend()),
                  const SizedBox(width: 16),
                  const Expanded(flex: 2, child: _Collections()),
                ],
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Action('New loan', Icons.add, () => context.go('/loans/new')),
                _Action(
                  'Record payment',
                  Icons.payments_outlined,
                  () => context.go('/payments'),
                ),
                _Action(
                  'Borrowers',
                  Icons.people_outline,
                  () => context.go('/borrowers'),
                ),
                _Action(
                  'Collections',
                  Icons.calendar_month_outlined,
                  () => context.go('/collections'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color, this.note);
  final String label, note;
  final int value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          FittedBox(
            child: Text(
              formatPeso(value),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    ),
  );
}

class _Trend extends StatelessWidget {
  const _Trend();
  @override
  Widget build(BuildContext context) {
    final groups = [18, 23, 20, 27, 31, 30].indexed
        .map(
          (e) => BarChartGroupData(
            x: e.$1,
            barRods: [
              BarChartRodData(
                toY: e.$2.toDouble(),
                color: AppColors.blue600,
                width: 22,
              ),
            ],
          ),
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collections trend',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Demo collections for the last 6 months',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: Semantics(
                label:
                    'Monthly collections: 180, 230, 205, 268, 312, 298 thousand pesos',
                child: BarChart(
                  BarChartData(
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    barGroups: groups,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Collections extends StatelessWidget {
  const _Collections();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('Maria Dela Cruz', 'LN-0087', 260000),
      ('Ramon Santos', 'LN-0104', 500000),
      ('Ana Perez', 'LN-0112', 260000),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's collections",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    item.$1.split(' ').map((e) => e[0]).take(2).join(),
                  ),
                ),
                title: Text(
                  item.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${item.$2} · ${formatPeso(item.$3)}'),
                trailing: const Chip(label: Text('Due today')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    height: 76,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.blue600),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
