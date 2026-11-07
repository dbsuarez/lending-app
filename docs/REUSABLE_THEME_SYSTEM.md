# Reusable Flutter Theme System

This project includes a portable Material 3 theme system with:

- System, light, and dark appearance modes
- Five preset seed-color palettes
- A custom hexadecimal seed color
- Automatic Material 3 light and dark color-scheme generation
- Riverpod state management
- A reusable settings panel

The default configuration is **System** mode with the **Ocean Blue** palette.

## Files to copy

Copy these files into the same relative locations in another Flutter project:

```text
lib/
  app/theme/
    app_theme.dart
    theme_mode_provider.dart
  core/theme/
    app_palette.dart
    palette_provider.dart
    theme_preferences_panel.dart
```

`app_theme.dart` also contains Lending Manager's `AppColors` constants. Another project may keep them, rename them, or replace them with its own design tokens. The reusable palette system itself depends on the selected seed color, not those fixed constants.

## Dependency

Add Riverpod:

```yaml
dependencies:
  flutter_riverpod: ^3.3.2
```

Wrap the application in `ProviderScope`:

```dart
void main() {
  runApp(const ProviderScope(child: MyApp()));
}
```

## Connect it to MaterialApp

The root app must be a `ConsumerWidget` so it rebuilds when the user changes the mode or palette:

```dart
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      theme: AppTheme.lightFor(palette.seed),
      darkTheme: AppTheme.darkFor(palette.seed),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}
```

For `MaterialApp.router`, use the same `theme`, `darkTheme`, and `themeMode` properties.

## Add the settings controls

Place the reusable panel anywhere in a settings page:

```dart
const Card(
  child: ThemePreferencesPanel(),
)
```

The panel provides:

- System, Light, and Dark segmented controls
- Ocean Blue, Emerald, Royal Violet, Sunset Orange, and Graphite presets
- A Custom action that accepts `#RRGGBB`
- A live color preview before applying a custom seed

## Select themes programmatically

Set a mode:

```dart
ref.read(themeModeProvider.notifier).select(ThemeMode.dark);
```

Select a preset:

```dart
ref.read(paletteProvider.notifier).select(AppPalettes.emerald);
```

Select a custom seed:

```dart
ref.read(paletteProvider.notifier).selectCustom(const Color(0xFFB423B9));
```

## Add or change presets

Edit `AppPalettes` in `app_palette.dart`:

```dart
static const rose = AppPalette(
  id: 'rose',
  name: 'Rose',
  seed: Color(0xFFE11D68),
);

static const presets = [ocean, emerald, violet, sunset, graphite, rose];
```

IDs must be stable and unique. The settings panel renders `AppPalettes.presets` automatically.

## Project-specific styling rule

Widgets should prefer colors from the active theme:

```dart
final colors = Theme.of(context).colorScheme;

Container(color: colors.surface);
Icon(Icons.add, color: colors.primary);
Text('Title', style: TextStyle(color: colors.onSurface));
```

Avoid hard-coded brand colors inside feature widgets if they should react to palette changes. Fixed semantic colors such as success, warning, and danger may remain centralized design tokens when consistent meaning is more important than palette variation.

## Persistence

The current providers intentionally keep preferences in memory. The app starts in System/Ocean Blue after every full launch. To persist choices, store these values with `shared_preferences` or the project's settings repository:

- `ThemeMode.name`
- `AppPalette.id`
- Custom seed as an eight-digit ARGB integer or six-digit RGB string

Load persisted values in the provider's initialization path before rendering the main application. Do not duplicate persistence logic inside the settings widget.

## Reuse checklist for another AI

1. Copy the five theme-system files.
2. Add `flutter_riverpod` and `ProviderScope`.
3. Make the root app a `ConsumerWidget`.
4. Wire `lightFor`, `darkFor`, and `themeMode` into `MaterialApp`.
5. Add `ThemePreferencesPanel` to Settings.
6. Replace feature-level hard-coded primary colors with `ColorScheme` values.
7. Add persistence only if the target project requires preferences across launches.
8. Test System, Light, Dark, every preset, and a custom hex color at mobile and desktop sizes.
