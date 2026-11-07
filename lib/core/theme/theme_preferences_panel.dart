import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/theme_mode_provider.dart';
import 'app_palette.dart';
import 'palette_provider.dart';

/// Portable Riverpod-powered theme controls. Copy the core/theme folder and
/// theme_mode_provider.dart into another Flutter project to reuse it.
class ThemePreferencesPanel extends ConsumerWidget {
  const ThemePreferencesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final palette = ref.watch(paletteProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Choose a mode and color palette'),
          ),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (value) =>
                ref.read(themeModeProvider.notifier).select(value.first),
          ),
          const SizedBox(height: 18),
          Text('Color palette', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in AppPalettes.presets)
                ChoiceChip(
                  selected: palette.id == preset.id,
                  avatar: CircleAvatar(backgroundColor: preset.seed),
                  label: Text(preset.name),
                  onSelected: (_) =>
                      ref.read(paletteProvider.notifier).select(preset),
                ),
              ActionChip(
                avatar: CircleAvatar(
                  backgroundColor: palette.isCustom ? palette.seed : null,
                  child: palette.isCustom
                      ? null
                      : const Icon(Icons.colorize, size: 16),
                ),
                label: Text(
                  palette.isCustom ? 'Custom #${_hex(palette.seed)}' : 'Custom',
                ),
                onPressed: () async {
                  final color = await showDialog<Color>(
                    context: context,
                    builder: (_) => _CustomColorDialog(initial: palette.seed),
                  );
                  if (color != null) {
                    ref.read(paletteProvider.notifier).selectCustom(color);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _hex(Color color) =>
      color.toARGB32().toRadixString(16).substring(2).toUpperCase();
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});
  final Color initial;
  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late final TextEditingController controller = TextEditingController(
    text: '#${ThemePreferencesPanel._hex(widget.initial)}',
  );
  Color? preview;

  Color? parse() {
    var value = controller.text.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null || value.length != 8 ? null : Color(parsed);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom palette'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter a six-digit hex color. Flutter generates matching light and dark schemes from this seed.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          autofocus: true,
          maxLength: 7,
          decoration: const InputDecoration(
            labelText: 'Seed color',
            hintText: '#1463F3',
          ),
          onChanged: (_) => setState(() => preview = parse()),
        ),
        const SizedBox(height: 8),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: preview ?? widget.initial,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text(
            'Palette preview',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: parse() == null
            ? null
            : () => Navigator.pop(context, parse()),
        child: const Text('Use color'),
      ),
    ],
  );
}
