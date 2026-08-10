import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_store.dart';

const _themeModeKey = 'reproot-theme-mode';

class ThemeModeController extends Notifier<ThemeMode> {
  late SessionStore _store;

  @override
  ThemeMode build() {
    _store = ref.read(sessionStoreProvider);
    return switch (_store.read(_themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _store.write(_themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
