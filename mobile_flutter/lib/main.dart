import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/session/session_store.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Warm the session cache before the first frame so the role chooser can
  // decide synchronously whether to skip straight to a tab shell.
  final container = ProviderContainer();
  final store = SessionStore(container.read(secureStorageProvider));
  await store.load();

  runApp(
    ProviderScope(
      overrides: [sessionStoreProvider.overrideWithValue(store)],
      child: const CoachFlowApp(),
    ),
  );
}

class CoachFlowApp extends ConsumerWidget {
  const CoachFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'CoachFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follows the OS setting, matching the Ionic app's
      // @media (prefers-color-scheme: dark).
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
