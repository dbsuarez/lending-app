import 'package:flutter/material.dart';

/// Scrollable list of cards that fits as many columns as the width allows.
///
/// Used by the narrow-screen layouts of list screens: one column on phones,
/// two or three on small tablets, landscape phones, and narrow windows.
/// Cards in the same row share the row's height.
class ResponsiveCardList extends StatelessWidget {
  const ResponsiveCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 240,
    this.maxColumns = 3,
    this.spacing = 8,
    this.padding,
    this.physics,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  /// Number of columns that fit [width] with each at least [minItemWidth].
  static int columnsFor(
    double width, {
    double minItemWidth = 240,
    int maxColumns = 3,
    double spacing = 8,
  }) => ((width + spacing) / (minItemWidth + spacing)).floor().clamp(
    1,
    maxColumns,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = columnsFor(
        constraints.maxWidth,
        minItemWidth: minItemWidth,
        maxColumns: maxColumns,
        spacing: spacing,
      );
      if (columns == 1) {
        return ListView.separated(
          padding: padding,
          physics: physics,
          itemCount: itemCount,
          separatorBuilder: (_, _) => SizedBox(height: spacing),
          itemBuilder: itemBuilder,
        );
      }
      final rowCount = (itemCount / columns).ceil();
      return ListView.separated(
        padding: padding,
        physics: physics,
        itemCount: rowCount,
        separatorBuilder: (_, _) => SizedBox(height: spacing),
        itemBuilder: (context, row) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) SizedBox(width: spacing),
                Expanded(
                  child: row * columns + column < itemCount
                      ? itemBuilder(context, row * columns + column)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
