import 'package:flutter/material.dart';

@immutable
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.seed,
    this.isCustom = false,
  });
  final String id;
  final String name;
  final Color seed;
  final bool isCustom;
}

abstract final class AppPalettes {
  static const ocean = AppPalette(
    id: 'ocean',
    name: 'Ocean Blue',
    seed: Color(0xFF1463F3),
  );
  static const emerald = AppPalette(
    id: 'emerald',
    name: 'Emerald',
    seed: Color(0xFF168451),
  );
  static const violet = AppPalette(
    id: 'violet',
    name: 'Royal Violet',
    seed: Color(0xFF6744DC),
  );
  static const sunset = AppPalette(
    id: 'sunset',
    name: 'Sunset Orange',
    seed: Color(0xFFF06432),
  );
  static const graphite = AppPalette(
    id: 'graphite',
    name: 'Graphite',
    seed: Color(0xFF475569),
  );
  static const presets = [ocean, emerald, violet, sunset, graphite];
  static AppPalette custom(Color seed) =>
      AppPalette(id: 'custom', name: 'Custom', seed: seed, isCustom: true);
}
