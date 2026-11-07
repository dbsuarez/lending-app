import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../preferences/filter_defaults.dart';

/// A table's remembered layout: hidden columns and custom widths (by label).
@immutable
class TableLayout {
  const TableLayout({this.hidden = const {}, this.widths = const {}});
  final Set<String> hidden;
  final Map<String, double> widths;
}

/// Per-table column visibility and widths, remembered on this device.
class ColumnPrefs extends Notifier<TableLayout> {
  ColumnPrefs(this.tableId);
  final String tableId;

  String get _hiddenKey => 'columns_hidden.$tableId';
  String get _widthsKey => 'columns_width.$tableId';

  @override
  TableLayout build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final widths = <String, double>{};
    for (final entry in prefs?.getStringList(_widthsKey) ?? const <String>[]) {
      final at = entry.lastIndexOf('=');
      final width = at < 0 ? null : double.tryParse(entry.substring(at + 1));
      if (width != null) widths[entry.substring(0, at)] = width;
    }
    return TableLayout(
      hidden: (prefs?.getStringList(_hiddenKey) ?? const []).toSet(),
      widths: widths,
    );
  }

  Future<void> setHidden(String label, bool hidden) async {
    final next = {...state.hidden};
    hidden ? next.add(label) : next.remove(label);
    state = TableLayout(hidden: next, widths: state.widths);
    await ref.read(sharedPreferencesProvider)?.setStringList(_hiddenKey, [
      ...next,
    ]);
  }

  /// Live update while dragging; call [saveWidths] when the drag ends.
  void setWidth(String label, double width) => state = TableLayout(
    hidden: state.hidden,
    widths: {...state.widths, label: width},
  );

  Future<void> saveWidths() async =>
      ref.read(sharedPreferencesProvider)?.setStringList(_widthsKey, [
        for (final e in state.widths.entries)
          '${e.key}=${e.value.toStringAsFixed(0)}',
      ]);

  Future<void> showAll() async {
    state = TableLayout(widths: state.widths);
    await ref.read(sharedPreferencesProvider)?.remove(_hiddenKey);
  }

  Future<void> resetWidths() async {
    state = TableLayout(hidden: state.hidden);
    await ref.read(sharedPreferencesProvider)?.remove(_widthsKey);
  }
}

final columnPrefsProvider =
    NotifierProvider.family<ColumnPrefs, TableLayout, String>(ColumnPrefs.new);

/// Which columns of a table are visible and how wide, with helpers to apply
/// that to a [DataTable] whose columns/cells are written in full order.
class ColumnView {
  ColumnView(
    this.labels,
    this.layout, {
    this.locked = const {0},
    this.onResize,
    this.onResizeEnd,
  });
  final List<String> labels;
  final TableLayout layout;

  /// Column indexes that can never be hidden (the row's identity).
  final Set<int> locked;
  final void Function(String label, double width)? onResize;
  final VoidCallback? onResizeEnd;

  late final List<int> visible = [
    for (var i = 0; i < labels.length; i++)
      if (locked.contains(i) || !layout.hidden.contains(labels[i])) i,
  ];

  bool isVisible(int index) => visible.contains(index);

  double? _width(int index) => layout.widths[labels[index]];

  /// Keeps only the visible entries.
  List<T> pick<T>(List<T> all) => [for (final i in visible) all[i]];

  /// A row's visible cells, sized to any custom column width.
  List<DataCell> cells(List<DataCell> all) => [
    for (final i in visible)
      _width(i) == null
          ? all[i]
          : DataCell(
              SizedBox(
                width: _width(i),
                child: DefaultTextStyle.merge(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  child: all[i].child,
                ),
              ),
              onTap: all[i].onTap,
              placeholder: all[i].placeholder,
              showEditIcon: all[i].showEditIcon,
            ),
  ];

  /// Visible columns with a resize handle; sort callbacks still receive the
  /// original column index.
  List<DataColumn> columns(List<DataColumn> all) => [
    for (final i in visible)
      DataColumn(
        label: _ResizableHeader(
          width: _width(i),
          onResize: onResize == null ? null : (w) => onResize!(labels[i], w),
          onResizeEnd: onResizeEnd,
          child: all[i].label,
        ),
        numeric: all[i].numeric,
        tooltip: all[i].tooltip,
        onSort: all[i].onSort == null
            ? null
            : (_, ascending) => all[i].onSort!(i, ascending),
      ),
  ];

  /// Maps the screen's sort column (original index) to the visible index.
  int? sortIndex(int? original) {
    if (original == null) return null;
    final at = visible.indexOf(original);
    return at < 0 ? null : at;
  }
}

/// Header content plus a thin drag handle on its right edge.
class _ResizableHeader extends StatefulWidget {
  const _ResizableHeader({
    required this.child,
    required this.width,
    this.onResize,
    this.onResizeEnd,
  });
  final Widget child;
  final double? width;
  final ValueChanged<double>? onResize;
  final VoidCallback? onResizeEnd;

  @override
  State<_ResizableHeader> createState() => _ResizableHeaderState();
}

class _ResizableHeaderState extends State<_ResizableHeader> {
  final _contentKey = GlobalKey();
  double _start = 0;

  static const _handle = 12.0;

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.width == null)
          content
        else
          SizedBox(
            width: (widget.width! - _handle).clamp(24, 2000),
            child: DefaultTextStyle.merge(
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              child: content,
            ),
          ),
        if (widget.onResize != null)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {
                final box =
                    _contentKey.currentContext?.findRenderObject()
                        as RenderBox?;
                _start = widget.width ?? ((box?.size.width ?? 80) + _handle);
              },
              onHorizontalDragUpdate: (details) {
                _start = (_start + details.delta.dx).clamp(48, 640);
                widget.onResize!(_start);
              },
              onHorizontalDragEnd: (_) => widget.onResizeEnd?.call(),
              child: SizedBox(
                width: _handle,
                height: 28,
                child: Center(
                  child: Container(
                    width: 2,
                    height: 16,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Wraps a table with a small floating button (top-right) to show or hide
/// columns, and makes headers resizable; both are remembered per table.
class ColumnToggle extends ConsumerWidget {
  const ColumnToggle({
    super.key,
    required this.tableId,
    required this.labels,
    required this.builder,
    this.locked = const {0},
  });

  final String tableId;
  final List<String> labels;
  final Set<int> locked;
  final Widget Function(ColumnView view) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(columnPrefsProvider(tableId));
    final prefs = ref.read(columnPrefsProvider(tableId).notifier);
    final view = ColumnView(
      labels,
      layout,
      locked: locked,
      onResize: prefs.setWidth,
      onResizeEnd: prefs.saveWidths,
    );
    return Stack(
      children: [
        builder(view),
        Positioned(
          top: 6,
          right: 6,
          child: MenuAnchor(
            menuChildren: [
              for (var i = 0; i < labels.length; i++)
                if (!locked.contains(i))
                  CheckboxMenuButton(
                    value: !layout.hidden.contains(labels[i]),
                    closeOnActivate: false,
                    onChanged: (show) =>
                        prefs.setHidden(labels[i], show == false),
                    child: Text(labels[i]),
                  ),
              const Divider(height: 1),
              if (layout.hidden.isNotEmpty)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.visibility_outlined, size: 18),
                  onPressed: prefs.showAll,
                  child: const Text('Show all columns'),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.restart_alt, size: 18),
                onPressed: layout.widths.isEmpty ? null : prefs.resetWidths,
                child: const Text('Reset column widths'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.info_outline, size: 18),
                onPressed: null,
                child: const Text('Drag a header\'s right edge to resize'),
              ),
            ],
            builder: (context, controller, _) => Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: 'Show, hide or resize columns',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: Icon(
                  layout.hidden.isEmpty && layout.widths.isEmpty
                      ? Icons.view_column_outlined
                      : Icons.view_column,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
