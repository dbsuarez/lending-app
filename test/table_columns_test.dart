import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/core/preferences/filter_defaults.dart';
import 'package:lending_manager/core/widgets/table_columns.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ColumnView keeps the first column and maps sort indexes', () {
    final view = ColumnView([
      'Reference',
      'Borrower',
      'Total',
      'Status',
    ], const TableLayout(hidden: {'Reference', 'Total'}));
    // Locked first column stays even if marked hidden.
    expect(view.visible, [0, 1, 3]);
    expect(view.pick(['a', 'b', 'c', 'd']), ['a', 'b', 'd']);
    expect(view.sortIndex(3), 2);
    expect(view.sortIndex(2), isNull); // sorted column is hidden
    int? sortedBy;
    final cols = view.columns([
      for (final l in ['Reference', 'Borrower', 'Total', 'Status'])
        DataColumn(label: Text(l), onSort: (i, _) => sortedBy = i),
    ]);
    cols[2].onSort!(2, true); // visible index 2 = original "Status"
    expect(sortedBy, 3);
  });

  test('hidden columns and widths are remembered per table', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    final c = make();
    addTearDown(c.dispose);
    final loans = c.read(columnPrefsProvider('loans').notifier);
    await loans.setHidden('Principal', true);
    loans.setWidth('Borrower', 220);
    await loans.saveWidths();
    expect(c.read(columnPrefsProvider('payments')).hidden, isEmpty);

    final again = make(); // app restart
    addTearDown(again.dispose);
    final layout = again.read(columnPrefsProvider('loans'));
    expect(layout.hidden, {'Principal'});
    expect(layout.widths['Borrower'], 220);

    await again.read(columnPrefsProvider('loans').notifier).resetWidths();
    expect(again.read(columnPrefsProvider('loans')).widths, isEmpty);
    expect(again.read(columnPrefsProvider('loans')).hidden, {'Principal'});
  });

  testWidgets('the floating button hides a column', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: ColumnToggle(
              tableId: 't',
              labels: const ['Name', 'Phone'],
              builder: (view) => DataTable(
                columns: view.columns(const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Phone')),
                ]),
                rows: [
                  DataRow(
                    cells: view.cells(const [
                      DataCell(Text('Ana')),
                      DataCell(Text('0917')),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('0917'), findsOneWidget);
    await tester.tap(find.byTooltip('Customize columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Phone'));
    await tester.pumpAndSettle();
    expect(find.text('0917'), findsNothing);
    expect(prefs.getStringList('columns_hidden.t'), ['Phone']);
  });
}
