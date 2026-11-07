import 'package:flutter/material.dart';
import 'info_tip.dart';

/// Lays metric cards out in equal-width columns: two on phones, more as the
/// width allows (each column at least [minItemWidth], at most [maxColumns]).
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    super.key,
    required this.children,
    this.minItemWidth = 150,
    this.maxColumns = 6,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          ((constraints.maxWidth + spacing) / (minItemWidth + spacing))
              .floor()
              .clamp(2, maxColumns);
      final width = (constraints.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// A compact label/value card for [MetricGrid]. Long values scale down
/// instead of overflowing narrow columns.
class MetricCard extends StatelessWidget {
  const MetricCard(this.label, this.value, {super.key, this.info});
  final String label, value;

  /// Optional glossary term; shows an ⓘ explanation next to the label.
  final String? info;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (info != null) InfoTip(info!, size: 16),
              ],
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
