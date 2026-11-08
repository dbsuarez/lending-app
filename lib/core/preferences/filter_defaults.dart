import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../undo/undo_controller.dart';

/// Device preferences, loaded once in main() so lists open on the saved
/// default immediately. Null in tests (falls back to in-memory).
final sharedPreferencesProvider = Provider<SharedPreferences?>((_) => null);

/// Remembered default for each list filter (per device).
class FilterDefaults {
  FilterDefaults(this._prefs);
  final SharedPreferences? _prefs;
  final _memory = <String, String>{};

  static String _key(String list) => 'filter_default.$list';

  String get(String list, String fallback) =>
      _prefs?.getString(_key(list)) ?? _memory[_key(list)] ?? fallback;

  Future<void> set(String list, String value) async {
    _memory[_key(list)] = value;
    await _prefs?.setString(_key(list), value);
  }
}

final filterDefaultsProvider = Provider<FilterDefaults>(
  (ref) => FilterDefaults(ref.watch(sharedPreferencesProvider)),
);

/// A filter dropdown whose options can be long-pressed to make them the
/// remembered default for this list.
class DefaultableFilterDropdown extends ConsumerWidget {
  const DefaultableFilterDropdown({
    super.key,
    required this.listKey,
    required this.listName,
    required this.label,
    required this.value,
    required this.fallback,
    required this.options,
    required this.onChanged,
  });

  /// Storage key, e.g. 'loans.status'.
  final String listKey;

  /// Shown in the confirmation, e.g. 'Loans'.
  final String listName;
  final String label, value, fallback;
  final List<(String value, String label)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaults = ref.watch(filterDefaultsProvider);
    final current = defaults.get(listKey, fallback);
    String labelOf(String v) =>
        options.firstWhere((o) => o.$1 == v, orElse: () => (v, v)).$2;
    return DropdownButtonFormField<String>(
      // Rebuild when the value changes from outside (a long-press default).
      key: ValueKey('$listKey:$value'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      selectedItemBuilder: (_) => [
        // Matches the item order below (hint first, then options).
        const SizedBox.shrink(),
        for (final option in options)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(option.$2, overflow: TextOverflow.ellipsis),
          ),
      ],
      items: [
        DropdownMenuItem<String>(
          enabled: false,
          value: '__hint__',
          child: Text(
            'Long-press an option to make it the default',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final option in options)
          DropdownMenuItem<String>(
            value: option.$1,
            child: Builder(
              builder: (itemContext) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () async {
                  HapticFeedback.mediumImpact();
                  // Close the menu without changing the selection, then save.
                  Navigator.of(itemContext).pop();
                  await defaults.set(listKey, option.$1);
                  onChanged(option.$1);
                  if (context.mounted) {
                    undoOf(context).notify(
                      '"${labelOf(option.$1)}" is now the default for $listName.',
                    );
                  }
                },
                // Fill the whole row: on touch screens the finger often lands
                // beside the text, which would otherwise be a plain tap.
                child: SizedBox(
                  width: double.infinity,
                  height: kMinInteractiveDimension,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    // Plain-text marker: reliable on every renderer, and
                    // clearer than an icon.
                    child: Text.rich(
                      TextSpan(
                        text: option.$2,
                        children: [
                          if (option.$1 == current)
                            TextSpan(
                              text: '  · default',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != '__hint__') onChanged(v);
      },
    );
  }
}
