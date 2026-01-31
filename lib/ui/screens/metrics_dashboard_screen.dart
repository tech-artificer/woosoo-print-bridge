import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/print_job.dart';
import '../../state/app_controller.dart';

class MetricsDashboardScreen extends ConsumerWidget {
  const MetricsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);

    final pending = st.pendingCount;
    final printing = ctrl.printingCount;
    final awaitingAck = ctrl.awaitingAckCount;
    final success = st.successCount;
    final failed = st.failedCount;
    final totalJobs = st.queue.length;
    final completed = success + failed;
    final successRate = completed == 0 ? '—' : '${((success / completed) * 100).toStringAsFixed(1)}%';

    final reconnectTotal = ctrl.reconnectAttemptTotal;
    final reconnectMax = ctrl.reconnectAttemptMax;
    final lastReconnect = ctrl.lastReconnectAttempt;
    final lastJobTime = ctrl.lastJobTime;
    final uptime = ctrl.uptime;

    final recent = ctrl.recentJobs(limit: 5);
    final lastError = (st.lastError ?? '').trim();
    final printerError = (st.printer.error ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metrics Dashboard'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ctrl.forcePoll(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _card('Device Health', [
                _kv('Initialized', st.initialized ? 'Yes' : 'No'),
                _kv('Device ID', st.config.deviceId ?? '—'),
                _kv('Session', st.sessionId?.toString() ?? '—'),
                _kvWithIndicator('Network', st.networkConnected, onlineText: 'Online', offlineText: 'Offline'),
                _kvWithIndicator('WebSocket', st.wsConnected, onlineText: 'Connected', offlineText: 'Disconnected'),
              ]),
              const SizedBox(height: 12),
              _card('Printer Health', [
                _kvWithIndicator('Printer', st.printer.connected, onlineText: 'Connected', offlineText: 'Disconnected'),
                _kv('Name', st.config.printerName ?? '—'),
                _kv('Address', st.config.printerAddress ?? '—'),
                _kv('Last Error', printerError.isEmpty ? '—' : printerError),
              ]),
              const SizedBox(height: 12),
              _card('Print Reliability', [
                _kv('Total Jobs', totalJobs.toString(), valueKey: const Key('metric_total_jobs')),
                _kv('Pending', pending.toString(), valueKey: const Key('metric_pending')),
                _kv('Printing', printing.toString(), valueKey: const Key('metric_printing')),
                _kv('Awaiting ACK', awaitingAck.toString(), valueKey: const Key('metric_awaiting_ack')),
                _kv('Success', success.toString(), valueKey: const Key('metric_success')),
                _kv('Failed', failed.toString(), valueKey: const Key('metric_failed')),
                _kv('Success Rate', successRate, valueKey: const Key('metric_success_rate')),
              ]),
              const SizedBox(height: 12),
              _card('Reconnect Metrics', [
                _kv('Reconnect Attempts (Total)', reconnectTotal.toString(), valueKey: const Key('metric_reconnect_total')),
                _kv('Reconnect Attempts (Max)', reconnectMax.toString(), valueKey: const Key('metric_reconnect_max')),
                _kv('Last Reconnect', _formatDate(lastReconnect), valueKey: const Key('metric_reconnect_last')),
              ]),
              const SizedBox(height: 12),
              _card('Uptime & Activity', [
                _kv('Uptime', _formatDuration(uptime), valueKey: const Key('metric_uptime')),
                _kv('Last Job', _formatDate(lastJobTime), valueKey: const Key('metric_last_job')),
              ]),
              if (lastError.isNotEmpty) ...[
                const SizedBox(height: 12),
                _card('Last Error', [
                  Text(lastError, style: const TextStyle(color: Colors.red)),
                ]),
              ],
              const SizedBox(height: 12),
              _card('Recent Activity', [
                if (recent.isEmpty)
                  const Text('No recent activity')
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recent.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (_, index) {
                      final job = recent[index];
                      final status = _prettyStatus(job.status);
                      final time = _formatDate(job.printedAt ?? job.createdAt);
                      final subtitle = job.lastError != null && job.lastError!.isNotEmpty
                          ? '$status • $time • ${job.lastError}'
                          : '$status • $time';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_statusIcon(job.status), color: _statusColor(job.status)),
                        title: Text('print_event_id=${job.printEventId}'),
                        subtitle: Text(subtitle),
                        trailing: Text('retry=${job.retryCount}'),
                      );
                    },
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Key? valueKey}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 160, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v, key: valueKey)),
          ],
        ),
      );

  Widget _kvWithIndicator(String k, bool connected, {String onlineText = 'Connected', String offlineText = 'Disconnected'}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 160, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Icon(
              connected ? Icons.check_circle : Icons.cancel,
              color: connected ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(connected ? onlineText : offlineText),
          ],
        ),
      );

  Widget _card(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    if (minutes > 0 || hours > 0 || days > 0) parts.add('${minutes}m');
    parts.add('${seconds}s');
    return parts.join(' ');
  }

  String _formatDate(DateTime? dt) => dt == null ? '—' : dt.toIso8601String();

  String _prettyStatus(PrintJobStatus status) {
    final text = status.name.replaceAll('_', ' ');
    return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  IconData _statusIcon(PrintJobStatus status) {
    switch (status) {
      case PrintJobStatus.pending:
        return Icons.schedule;
      case PrintJobStatus.printing:
        return Icons.print;
      case PrintJobStatus.printed_awaiting_ack:
        return Icons.timelapse;
      case PrintJobStatus.success:
        return Icons.check_circle;
      case PrintJobStatus.failed:
        return Icons.error;
      case PrintJobStatus.cancelled:
        return Icons.cancel;
    }
  }

  Color _statusColor(PrintJobStatus status) {
    switch (status) {
      case PrintJobStatus.pending:
        return Colors.orange;
      case PrintJobStatus.printing:
        return Colors.blue;
      case PrintJobStatus.printed_awaiting_ack:
        return Colors.purple;
      case PrintJobStatus.success:
        return Colors.green;
      case PrintJobStatus.failed:
        return Colors.red;
      case PrintJobStatus.cancelled:
        return Colors.grey;
    }
  }
}
