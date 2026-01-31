import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  final GoRouter router;
  const AppShell({super.key, required this.child, required this.router});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;

  @override
  Widget build(BuildContext context) {
    final router = widget.router;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final location = router.routeInformationProvider.value.uri.path;

        // If we are not on home, pop the route stack first.
        if (location != '/') {
          if (router.canPop()) {
            router.pop();
          } else {
            router.go('/');
          }
          return;
        }

        // Home screen: require a second back press within 2 seconds to exit.
        final now = DateTime.now();
        final shouldExit = _lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2);
        _lastBack = now;

        if (shouldExit) {
          await SystemNavigator.pop();
          return;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Press back again to exit')),
          );
        }
      },
      child: widget.child,
    );
  }
}
