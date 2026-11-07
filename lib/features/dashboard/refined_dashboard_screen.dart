import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/formatting.dart';

class RefinedDashboardScreen extends StatelessWidget {
  const RefinedDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final mobile = box.maxWidth < 700;
      return SingleChildScrollView(
        padding: EdgeInsets.all(mobile ? 14 : 16),
        child: Column(
          children: [
            _Hero(mobile: mobile),
            const SizedBox(height: 10),
            GridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: mobile ? 2 : 4,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                mainAxisExtent: mobile ? 108 : 88,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                _Kpi(
                  'Outstanding Loans',
                  124800000,
                  Icons.account_balance_wallet_outlined,
                  Color(0xFFDCEFFF),
                  AppColors.blue600,
                  '14 active loans',
                ),
                _Kpi(
                  'Collections (This Month)',
                  31260000,
                  Icons.savings_outlined,
                  Color(0xFFDDF8E7),
                  AppColors.success,
                  '↑ 16.2% vs. last month',
                ),
                _Kpi(
                  'Due Today',
                  5200000,
                  Icons.event_outlined,
                  Color(0xFFF0E3FF),
                  AppColors.violet600,
                  '20 installments',
                ),
                _Kpi(
                  'Overdue',
                  18640000,
                  Icons.warning_amber_rounded,
                  Color(0xFFFFE1E4),
                  AppColors.danger,
                  '37 installments',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (mobile) ...[
              const SizedBox(height: 265, child: _DueCard()),
              const SizedBox(height: 10),
              const SizedBox(height: 265, child: _TrendCard()),
            ] else
              const SizedBox(
                height: 265,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _TrendCard()),
                    SizedBox(width: 10),
                    Expanded(flex: 2, child: _DueCard()),
                  ],
                ),
              ),
            if (!mobile) ...[
              const SizedBox(height: 10),
              const SizedBox(
                height: 185,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _PaymentsCard()),
                    SizedBox(width: 10),
                    Expanded(flex: 2, child: _StatusCard()),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Quick(
                  'New Loan',
                  Icons.add,
                  () => context.go('/loans/new'),
                  primary: true,
                ),
                _Quick(
                  'Record Payment',
                  Icons.credit_card_outlined,
                  () => context.go('/payments'),
                ),
                _Quick(
                  'Payment Schedule',
                  Icons.event_note_outlined,
                  () => context.go('/collections'),
                ),
                _Quick(
                  'Loan Calculator',
                  Icons.calculate_outlined,
                  () => context.go('/loans/new'),
                ),
                _Quick(
                  'Reports',
                  Icons.bar_chart_outlined,
                  () => context.go('/reports'),
                ),
                _Quick(
                  'Generate Document',
                  Icons.description_outlined,
                  () => context.go('/documents'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.mobile});
  final bool mobile;
  @override
  Widget build(BuildContext context) => Container(
    height: mobile ? 112 : 106,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .24),
          blurRadius: 14,
          offset: Offset(0, 5),
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
                AppColors.navy900,
                .55,
              ) ??
              AppColors.navy900,
        ],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _HeroBackdropPainter()),
        Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good Evening!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: mobile ? 23 : 26,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(
                          color: Color(0x33000000),
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Here's your lending business overview.",
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
            if (!mobile) const _HeroArt(),
          ],
        ),
      ],
    ),
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi(
    this.label,
    this.amount,
    this.icon,
    this.iconBg,
    this.color,
    this.note,
  );
  final String label, note;
  final int amount;
  final IconData icon;
  final Color iconBg, color;
  @override
  Widget build(BuildContext context) {
    final effectiveColor = color == AppColors.blue600
        ? Theme.of(context).colorScheme.primary
        : color;
    final effectiveBackground = color == AppColors.blue600
        ? Theme.of(context).colorScheme.primaryContainer
        : iconBg;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: effectiveBackground,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: effectiveColor, size: 22),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatPeso(amount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      color: effectiveColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard();
  @override
  Widget build(BuildContext context) {
    final values = [26.8, 31.26, 35.0];
    final data = BarChartData(
      maxY: 40,
      alignment: BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: 10,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 10,
            getTitlesWidget: (value, meta) => Text(
              '₱${value.toInt() * 10}K',
              style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ['Last Month', 'This Month', 'Target'][value.toInt()],
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      barGroups: values.indexed
          .map(
            (entry) => BarChartGroupData(
              x: entry.$1,
              barRods: [
                BarChartRodData(
                  toY: entry.$2,
                  width: 38,
                  color: entry.$1 == 1
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collections Trend',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const _PeriodPill(),
              ],
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Semantics(
                label:
                    'Collections: last month 268 thousand pesos, this month 312,600 pesos, target 350 thousand pesos',
                child: BarChart(data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Text(
      'This Month',
      style: TextStyle(
        color: Colors.white,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DueCard extends StatelessWidget {
  const _DueCard();
  @override
  Widget build(BuildContext context) {
    final rows = [
      ('DC', 'Dela Cruz, Maria', 'LN-0087', 260000),
      ('RS', 'Santos, Ramon', 'LN-0104', 500000),
      ('AP', 'Perez, Ana', 'LN-0112', 260000),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 7),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Today's Collections (15th)",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'View All',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final r in rows)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    minVerticalPadding: 3,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFFFFE9D2),
                      child: Text(
                        r.$1,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      r.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${r.$3} · Due Today',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    trailing: SizedBox(
                      width: 92,
                      child: Text(
                        formatPeso(r.$4),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Payments',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          const Row(
            children: [
              Expanded(flex: 2, child: _Head('Date & Time')),
              SizedBox(width: 12),
              Expanded(flex: 2, child: _Head('Borrower')),
              SizedBox(width: 12),
              Expanded(child: _Head('Amount', numeric: true)),
              SizedBox(width: 18),
              Expanded(child: _Head('Method')),
            ],
          ),
          for (final r in [
            ('2026-04-15 10:02', 'Dela Cruz, Maria', 260000, 'GCash'),
            ('2026-04-15 09:47', 'Santos, Ramon', 500000, 'AUB'),
            ('2026-04-15 09:30', 'Perez, Ana', 260000, 'Cash'),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(r.$1, style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text(
                        r.$2,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        formatPeso(r.$3),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(r.$4, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head(this.text, {this.numeric = false});
  final String text;
  final bool numeric;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: numeric ? TextAlign.right : TextAlign.left,
    style: TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 36,
                    sectionsSpace: 1,
                    sections: [
                      PieChartSectionData(
                        value: 69,
                        color: AppColors.success,
                        radius: 18,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: 5,
                        color: Colors.amber,
                        radius: 18,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: 26,
                        color: AppColors.danger,
                        radius: 18,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Loan Status Overview',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 7),
                _Legend(AppColors.success, 'Current', '98'),
                _Legend(Colors.amber, 'Due Soon', '7'),
                _Legend(AppColors.danger, 'Overdue', '37'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label, this.value);
  final Color color;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _Quick extends StatelessWidget {
  const _Quick(this.label, this.icon, this.tap, {this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback tap;
  final bool primary;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    height: 56,
    child: Card(
      color: primary
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).cardTheme.color,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: primary
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: primary
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HeroArt extends StatelessWidget {
  const _HeroArt();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          right: 2,
          bottom: 4,
          child: Icon(Icons.savings, color: Colors.amber.shade400, size: 78),
        ),
        const Positioned(
          right: 68,
          top: 10,
          child: Icon(
            Icons.assignment_turned_in_outlined,
            color: Colors.white,
            size: 76,
          ),
        ),
        const Positioned(
          right: 150,
          bottom: 10,
          child: Icon(Icons.eco, color: Color(0xFF9AD64D), size: 49),
        ),
        Positioned(
          right: 43,
          bottom: 3,
          child: Icon(
            Icons.monetization_on,
            color: Colors.amber.shade200,
            size: 38,
          ),
        ),
      ],
    ),
  );
}

class _HeroBackdropPainter extends CustomPainter {
  const _HeroBackdropPainter();
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
    final path = Path()
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
    canvas.drawPath(path, Paint()..color = const Color(0x1624B8FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
