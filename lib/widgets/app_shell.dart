import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'printer_status_banner.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  final GoRouter router;
  const AppShell({super.key, required this.child, required this.router});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;

  static const _navRoutes = ['/', '/queue', '/metrics', '/orders', '/settings'];
  static const _navIcons = [
    Icons.home_outlined,
    Icons.list_alt_outlined,
    Icons.bar_chart_outlined,
    Icons.history_outlined,
    Icons.settings_outlined,
  ];
  static const _navLabels = ['Status', 'Queue', 'Metrics', 'Orders', 'Settings'];

  @override
  void initState() {
    super.initState();
    widget.router.routeInformationProvider.addListener(_onRouteChange);
  }

  @override
  void dispose() {
    widget.router.routeInformationProvider.removeListener(_onRouteChange);
    super.dispose();
  }

  void _onRouteChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.router.routeInformationProvider.value.uri.path;
    final navIndex = _navRoutes.indexOf(location);
    final showNav = navIndex >= 0;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final loc = widget.router.routeInformationProvider.value.uri.path;

        // If we are not on home, pop the route stack first.
        if (loc != '/') {
          if (widget.router.canPop()) {
            widget.router.pop();
          } else {
            widget.router.go('/');
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
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            const PrinterStatusBanner(),
            Expanded(child: widget.child),
          ],
        ),
        bottomNavigationBar: showNav
            ? NavigationBar(
                selectedIndex: navIndex,
                onDestinationSelected: (i) {
                  if (i != navIndex) {
                    widget.router.go(_navRoutes[i]);
                  }
                },
                destinations: [
                  for (int i = 0; i < _navRoutes.length; i++)
                    NavigationDestination(
                      icon: Icon(_navIcons[i]),
                      label: _navLabels[i],
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
