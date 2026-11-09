import 'package:flutter/material.dart';

import 'window_title.dart';

/// Asks before an action that changes records in a way the user should
/// think about. Returns true only when the user presses [confirmLabel].
/// [destructive] colours the button as a warning (e.g. Revoke).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: WindowTitle(Text(title)),
      content: SizedBox(width: 440, child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
