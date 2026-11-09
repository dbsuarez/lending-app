import 'package:flutter/material.dart';

/// A pop-up window's title with a Back arrow in front, so every window can be
/// left the same way on phones and computers (not only by Cancel/Close or
/// tapping outside).
class WindowTitle extends StatelessWidget {
  const WindowTitle(this.child, {super.key, this.onBack});

  /// Usually a [Text].
  final Widget child;

  /// Defaults to closing the window.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Back',
        visualDensity: VisualDensity.compact,
        onPressed: onBack ?? () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back),
      ),
      const SizedBox(width: 4),
      Expanded(child: child),
    ],
  );
}
