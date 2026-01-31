import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/app_controller.dart';
import 'ui/router.dart' as app_router;
import 'widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RelayApp()));
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
      theme: ThemeData(useMaterial3: true),
      routerConfig: app_router.router,
      builder: (context, child) => AppShell(router: app_router.router, child: child ?? const SizedBox.shrink()),
    );
  }
}
