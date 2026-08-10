import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/api/api_client.dart';
import 'core/api/error_report_api.dart';
import 'core/config/env.dart';
import 'core/session/session_store.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertSecureBaseUrl();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Warm the session cache before the first frame so the role chooser can
  // decide synchronously whether to skip straight to a tab shell.
  final container = ProviderContainer();
  final store = SessionStore(container.read(secureStorageProvider));
  await store.load();

  // Built directly (not via Riverpod) so crash capture is live before the
  // ProviderScope exists — a crash during startup itself still gets reported.
  final errorReport = ErrorReportApi(buildDio(store), store);

  // Framework-caught errors (widget build/layout/paint failures).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    errorReport.report(
      details.exceptionAsString(),
      stackTrace: details.stack?.toString() ?? '',
    );
  };
  // Everything else uncaught — async errors, platform channel failures, etc.
  PlatformDispatcher.instance.onError = (error, stack) {
    errorReport.report(error.toString(), stackTrace: stack.toString());
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [sessionStoreProvider.overrideWithValue(store)],
      child: const RepRootApp(),
    ),
  );
}

class RepRootApp extends ConsumerWidget {
  const RepRootApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'RepRoot Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
