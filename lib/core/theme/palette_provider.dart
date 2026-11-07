import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_palette.dart';

class PaletteNotifier extends Notifier<AppPalette> {
  @override
  AppPalette build() => AppPalettes.ocean;
  void select(AppPalette palette) => state = palette;
  void selectCustom(Color seed) => state = AppPalettes.custom(seed);
}

final paletteProvider = NotifierProvider<PaletteNotifier, AppPalette>(
  PaletteNotifier.new,
);
