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
  bool _navOpen = false;

  static const _navRoutes = [
    '/',
    '/queue',
    '/metrics',
    '/orders',
    '/tools',
    '/logs',
    '/settings',
  ];
  static const _navIcons = [
    Icons.home_outlined,
    Icons.list_alt_outlined,
    Icons.bar_chart_outlined,
    Icons.history_outlined,
    Icons.construction_outlined,
    Icons.receipt_long_outlined,
    Icons.settings_outlined,
  ];
  static const _navLabels = [
    'Status',
    'Queue',
    'Metrics',
    'Orders',
    'Tools',
    'Logs',
    'Settings',
  ];

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

  void _toggleNav() {
    setState(() => _navOpen = !_navOpen);
  }

  void _closeNav() {
    if (_navOpen) setState(() => _navOpen = false);
  }

  void _goToRoute(String route) {
    _closeNav();
    if (widget.router.routeInformationProvider.value.uri.path != route) {
      widget.router.go(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.router.routeInformationProvider.value.uri.path;
    final navIndex = _navRoutes.indexOf(location);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (_navOpen) {
          _closeNav();
          return;
        }

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
        final shouldExit = _lastBack != null &&
            now.difference(_lastBack!) < const Duration(seconds: 2);
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
        body: Stack(
          children: [
            Column(
              children: [
                const PrinterStatusBanner(),
                Expanded(child: widget.child),
              ],
            ),
            if (_navOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeNav,
                  child: Container(color: Colors.black.withAlpha(80)),
                ),
              ),
            if (_navOpen)
              Positioned(
                right: 16,
                bottom: 88,
                child: _NavigationOverlay(
                  currentIndex: navIndex,
                  routes: _navRoutes,
                  icons: _navIcons,
                  labels: _navLabels,
                  onSelected: _goToRoute,
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Semantics(
                label: _navOpen ? 'Close navigation' : 'Open navigation',
                button: true,
                child: FloatingActionButton.small(
                  key: const ValueKey('app-shell-navigation-button'),
                  heroTag: 'app-shell-navigation',
                  onPressed: _toggleNav,
                  child: Icon(_navOpen ? Icons.close : Icons.menu),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationOverlay extends StatelessWidget {
  final int currentIndex;
  final List<String> routes;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<String> onSelected;

  const _NavigationOverlay({
    required this.currentIndex,
    required this.routes,
    required this.icons,
    required this.labels,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 8,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 184, maxWidth: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < routes.length; i++)
              ListTile(
                dense: true,
                leading: Icon(
                  icons[i],
                  color: i == currentIndex ? scheme.primary : null,
                ),
                title: Text(labels[i]),
                selected: i == currentIndex,
                onTap: () => onSelected(routes[i]),
              ),
          ],
        ),
      ),
    );
  }
}
