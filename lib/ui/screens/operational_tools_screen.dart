import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/app_controller.dart';

class OperationalToolsScreen extends ConsumerStatefulWidget {
  const OperationalToolsScreen({super.key});

  @override
  ConsumerState<OperationalToolsScreen> createState() =>
      _OperationalToolsScreenState();
}

class _OperationalToolsScreenState
    extends ConsumerState<OperationalToolsScreen> {
  String? _runningAction;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operational Tools'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (st.queuePaused) ...[
            _attentionCard(
              context,
              st.queuePauseReason ?? 'Queue paused. Check printer.',
              ctrl,
            ),
            const SizedBox(height: 16),
          ],
          _section(
            title: 'Recovery Actions',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _actionButton(
                    label: 'Restart WebSocket',
                    icon: Icons.cloud_sync,
                    onPressed: () =>
                        _runAction('Restart WebSocket', ctrl.restartWebSocket),
                  ),
                  _actionButton(
                    label: 'Force Poll',
                    icon: Icons.sync,
                    onPressed: () => _runAction('Force Poll', ctrl.forcePoll),
                  ),
                  _actionButton(
                    label: 'Flush Pending ACKs',
                    icon: Icons.task_alt,
                    onPressed: () =>
                        _runAction('Flush Pending ACKs', ctrl.flushPendingAcks),
                  ),
                  _actionButton(
                    label: 'Connect Printer',
                    icon: Icons.print,
                    onPressed: () => _runAction(
                      'Connect Printer',
                      () => _connectPrinter(ctrl),
                    ),
                  ),
                  _actionButton(
                    label: 'Resume Queue',
                    icon: Icons.play_arrow,
                    onPressed: () =>
                        _runAction('Resume Queue', ctrl.resumeQueue),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Live Status',
            children: [
              _statusRow(
                context,
                'WebSocket',
                st.wsConnected ? 'Connected' : 'Disconnected',
                st.wsConnected,
              ),
              _statusRow(
                context,
                'Printer',
                st.printer.connected
                    ? st.config.printerName ?? 'Connected'
                    : 'Not connected',
                st.printer.connected,
              ),
              _statusRow(
                context,
                'Network',
                st.networkConnected ? 'Online' : 'Offline',
                st.networkConnected,
              ),
              _statusRow(
                context,
                'Queue',
                st.queuePaused
                    ? 'Paused'
                    : '${st.pendingCount} pending, ${ctrl.awaitingAckCount} awaiting ACK',
                !st.queuePaused,
              ),
              _statusRow(
                context,
                'API URL',
                st.config.apiBaseUrl,
                st.config.apiBaseUrl.isNotEmpty,
              ),
              _statusRow(
                context,
                'WS URL',
                st.config.wsUrl,
                st.config.wsUrl.isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Navigation',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/queue'),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Open Queue'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/logs'),
                    icon: const Icon(Icons.article),
                    label: const Text('Open Logs'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/dead-letter'),
                    icon: const Icon(Icons.report),
                    label: const Text('Dead Letter'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings),
                    label: const Text('Settings'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _attentionCard(
    BuildContext context,
    String reason,
    AppController ctrl,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.report_problem, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                reason,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => _runAction('Resume Queue', ctrl.resumeQueue),
              child: const Text('Resume'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
  }) {
    final running = _runningAction == label;
    return ElevatedButton.icon(
      onPressed: _runningAction == null ? onPressed : null,
      icon: running
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(running ? 'Working...' : label),
    );
  }

  Widget _statusRow(
    BuildContext context,
    String label,
    String value,
    bool healthy,
  ) {
    final cs = Theme.of(context).colorScheme;
    final color = healthy ? cs.tertiary : cs.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(
            healthy ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _connectPrinter(AppController ctrl) async {
    final cfg = ref.read(appControllerProvider).config;
    final address = cfg.printerAddress;
    if (address == null || address.isEmpty) {
      throw StateError('Select a printer in Settings first.');
    }
    await ctrl.connectPrinterByAddress(address, name: cfg.printerName);
  }

  Future<void> _runAction(
    String label,
    Future<void> Function() action,
  ) async {
    setState(() => _runningAction = label);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label completed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _runningAction = null);
    }
  }
}
