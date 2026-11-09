import 'package:flutter/material.dart';

/// Label for a button that opens a menu: the text followed by ▾.
///
/// The app's convention (docs/UI_STANDARDS.md):
///   "Correct ▾"      opens a menu of choices
///   "Early Payoff…"  opens a window to fill in or confirm
///   "Edit Draft"     acts at once or goes to another page
class MenuLabel extends StatelessWidget {
  const MenuLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text),
      const SizedBox(width: 2),
      const Icon(Icons.arrow_drop_down, size: 20),
    ],
  );
}
