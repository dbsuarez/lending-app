import 'package:flutter/material.dart';

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final normalized = status.trim().toLowerCase();
    final (background, foreground) = switch (normalized) {
      'fully_paid' || 'paid' || 'verified' => (
        dark ? const Color(0xFF124E36) : const Color(0xFFD8F5E5),
        dark ? const Color(0xFF9BE5BD) : const Color(0xFF11633B),
      ),
      'active' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'pending' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      'rejected' ||
      'reversed' ||
      'cancelled' => (scheme.errorContainer, scheme.onErrorContainer),
      'draft' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label(normalized),
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _label(String value) => switch (value) {
    'fully_paid' || 'paid' => 'Paid',
    'pending' => 'Pending Verification',
    'verified' => 'Verified',
    'rejected' => 'Rejected',
    'reversed' => 'Reversed',
    'cancelled' => 'Cancelled',
    'active' => 'Active',
    'draft' => 'Draft',
    _ =>
      value
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
  };
}
