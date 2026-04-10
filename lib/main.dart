import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'state/app_controller.dart';
import 'ui/router.dart' as app_router;
import 'ui/theme/app_theme.dart';
import 'widgets/app_shell.dart';

Future<void> _logCrashToFile(String message) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final logsDir = Directory('${dir.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final crashFile = File('${logsDir.path}/crash_log.txt');
    final now = DateTime.now().toIso8601String();
    await crashFile.writeAsString('[$now] $message\n',
        mode: FileMode.append, flush: true);
  } catch (_) {
    // Last-resort logging must never crash the app.
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(_logCrashToFile(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack ?? ''}'));
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(_logCrashToFile('PlatformError: $error\n$stack'));
    return true;
  };

  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: RelayApp()));
    },
    (Object error, StackTrace stack) {
      unawaited(_logCrashToFile('ZoneError: $error\n$stack'));
      if (!kReleaseMode) {
        debugPrint('ZoneError: $error');
      }
    },
  );
}

class RelayApp extends ConsumerStatefulWidget {
  const RelayApp({super.key});

  @override
  ConsumerState<RelayApp> createState() => _RelayAppState();
}

class _RelayAppState extends ConsumerState<RelayApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appControllerProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Woosoo Relay Device',
      theme: WoosooTheme.themeData,
      routerConfig: app_router.router,
      builder: (context, child) => AppShell(
          router: app_router.router, child: child ?? const SizedBox.shrink()),
    );
  }
}
