import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';
import 'package:woosoo_relay_device/widgets/app_shell.dart';

class _TestAppController extends AppController {
  _TestAppController(Ref ref)
      : super(
          ref,
          LoggerService(),
          const DeviceConfig(
            apiBaseUrl: 'http://localhost',
            wsUrl: 'ws://localhost/app/test',
            deviceId: null,
            authToken: null,
            printerName: null,
            printerAddress: null,
            printerId: 'test-printer',
          ),
        );

  @override
  // The production controller reads providers during dispose; this widget test
  // only needs stable shell state, so teardown is intentionally inert.
  // ignore: must_call_super
  void dispose() {}
}

void main() {
  testWidgets('AppShell uses overlay navigation instead of bottom tabs',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Status screen')),
        ),
        GoRoute(
          path: '/queue',
          builder: (_, __) => const Scaffold(body: Text('Queue screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_TestAppController.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppShell(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('app-shell-navigation-button')),
        findsOneWidget);
    expect(find.text('Queue'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('app-shell-navigation-button')));
    await tester.pumpAndSettle();

    expect(find.text('Queue'), findsOneWidget);
  });
}
