import 'package:go_router/go_router.dart';
import 'screens/status_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/operational_tools_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/metrics_dashboard_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/orders_history_screen.dart';
import 'screens/dead_letter_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const StatusScreen()),
    GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
    GoRoute(path: '/metrics', builder: (_, __) => const MetricsDashboardScreen()),
    GoRoute(path: '/tools', builder: (_, __) => const OperationalToolsScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/logs', builder: (_, __) => const LogsScreen()),
    GoRoute(path: '/orders', builder: (_, __) => const OrdersHistoryScreen()),
    GoRoute(path: '/dead-letter', builder: (_, __) => const DeadLetterScreen()),
  ],
);
