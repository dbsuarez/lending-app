import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide messenger so transaction messages survive page navigation.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The single most recent undoable transaction.
class UndoEntry {
  UndoEntry({required this.message, required this.undo});

  /// What happened, e.g. "Payment verified and allocated."
  final String message;

  /// Reverses the transaction. Returns false (or throws) when the server
  /// refuses, e.g. because later activity depends on it.
  final Future<bool> Function() undo;
}

final undoControllerProvider = NotifierProvider<UndoController, UndoEntry?>(
  UndoController.new,
);

/// The undo/message controller from any widget, with or without a `ref`.
UndoController undoOf(BuildContext context) => ProviderScope.containerOf(
  context,
  listen: false,
).read(undoControllerProvider.notifier);

/// Single-level undo for transactions.
///
/// * [offer] after a successful undoable transaction: shows a snackbar with
///   Undo that stays until closed or replaced.
/// * [record] after any other transaction (or a failure): shows the message
///   and ends the previous undo, since undo is only valid until another
///   transaction is made.
/// * Closing the snackbar gives up the undo, so nothing is ever undoable
///   without a visible Undo button.
class UndoController extends Notifier<UndoEntry?> {
  @override
  UndoEntry? build() => null;

  void offer(String message, Future<bool> Function() undo) {
    final entry = UndoEntry(message: message, undo: undo);
    state = entry;
    _showUndo(entry);
  }

  /// A non-transaction message (e.g. "Link copied"). Shown briefly; the
  /// current Undo, if any, comes back afterwards and stays valid.
  void notify(String message) {
    final entry = state;
    _show(
      SnackBar(content: Text(message)),
      onClosed: (reason) {
        // `remove` means another message replaced this one; let it own the
        // screen (it will restore the Undo itself if needed).
        if (reason != SnackBarClosedReason.remove &&
            entry != null &&
            identical(state, entry)) {
          _showUndo(entry);
        }
      },
    );
  }

  void _showUndo(UndoEntry entry) {
    final message = entry.message;
    _show(
      SnackBar(
        content: Text(message),
        persist: true,
        showCloseIcon: true,
        action: SnackBarAction(label: 'Undo', onPressed: () => _run(entry)),
      ),
      onClosed: (reason) {
        // Closed by the user (✕ or swipe): give up this undo.
        if (reason != SnackBarClosedReason.action &&
            reason != SnackBarClosedReason.remove &&
            identical(state, entry)) {
          state = null;
        }
      },
    );
  }

  /// A transaction without undo (or a failed one). Persistent like [offer].
  void record(String message) {
    state = null;
    _show(SnackBar(content: Text(message), persist: true, showCloseIcon: true));
  }

  /// Ends the current undo without showing anything.
  void clear() {
    state = null;
    rootScaffoldMessengerKey.currentState?.removeCurrentSnackBar();
  }

  Future<void> _run(UndoEntry entry) async {
    if (!identical(state, entry)) return;
    state = null;
    bool undone;
    try {
      undone = await entry.undo();
    } catch (_) {
      undone = false;
    }
    _show(
      SnackBar(
        content: Text(
          undone
              ? 'Undone: ${entry.message}'
              : 'Could not undo. Later activity may depend on it, or it was '
                    'made by someone else.',
        ),
        persist: !undone,
        showCloseIcon: true,
      ),
    );
  }

  void _show(
    SnackBar snackBar, {
    void Function(SnackBarClosedReason reason)? onClosed,
  }) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.removeCurrentSnackBar();
    final controller = messenger.showSnackBar(snackBar);
    if (onClosed != null) controller.closed.then(onClosed);
  }
}
