import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/core/undo/undo_controller.dart';

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('undo snackbar stays until used, then runs the undo', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    var undone = 0;
    container.read(undoControllerProvider.notifier).offer(
      'Payment verified and allocated.',
      () async {
        undone++;
        return true;
      },
    );
    await tester.pumpAndSettle();
    // Does not auto-close: still there long after a normal snackbar would go.
    await tester.pump(const Duration(minutes: 5));
    expect(find.text('Payment verified and allocated.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(
      find.text('Undone: Payment verified and allocated.'),
      findsOneWidget,
    );
    expect(container.read(undoControllerProvider), isNull);
  });

  testWidgets('a new transaction ends the previous undo', (tester) async {
    final container = await _pumpApp(tester);
    final undo = container.read(undoControllerProvider.notifier);
    var firstUndone = false;
    undo.offer('Loan draft created.', () async => firstUndone = true);
    await tester.pumpAndSettle();
    undo.record('Payment rejected.');
    await tester.pumpAndSettle();
    expect(container.read(undoControllerProvider), isNull);
    expect(find.text('Undo'), findsNothing);
    expect(firstUndone, isFalse);
  });

  testWidgets('closing the snackbar gives up the undo', (tester) async {
    final container = await _pumpApp(tester);
    container
        .read(undoControllerProvider.notifier)
        .offer('Borrower archived.', () async => true);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(container.read(undoControllerProvider), isNull);
  });

  testWidgets('an info message does not cancel the undo, which comes back', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    final undo = container.read(undoControllerProvider.notifier);
    undo.offer('Customer status link created.', () async => true);
    await tester.pumpAndSettle();
    undo.notify('Customer link copied.');
    await tester.pumpAndSettle();
    expect(find.text('Customer link copied.'), findsOneWidget);
    // Let the info message time out; the Undo returns.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Customer status link created.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(container.read(undoControllerProvider), isNotNull);
  });

  testWidgets('a refused undo says so and keeps the message up', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    container
        .read(undoControllerProvider.notifier)
        .offer('Loan confirmed and disbursement recorded.', () async => false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(find.textContaining('Could not undo'), findsOneWidget);
  });
}
