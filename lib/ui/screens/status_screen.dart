import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/print_job.dart';
import '../../services/test_print_service.dart';
import '../../state/app_controller.dart';

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final testPrint = ref.read(testPrintServiceProvider);

    final queue = st.queue;
    final printingCount =
        queue.where((j) => j.status == PrintJobStatus.printing).length;
    final awaitingAckCount = queue
        .where((j) => j.status == PrintJobStatus.printed_awaiting_ack)
        .length;
    final lastJobTime = queue.isEmpty
        ? null
        : queue
            .map((j) => j.createdAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (prev, dt) {
            if (prev == null) return dt;
            return dt.isAfter(prev) ? dt : prev;
          });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Woosoo Relay Device'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ctrl.forcePoll(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _card('System', [
                _kv('Initialized', st.initialized ? 'Yes' : 'No'),
                _kv('Device ID', st.config.deviceId ?? '—'),
                _kv('Session', st.sessionId?.toString() ?? '—'),
                _kv('Platform', st.platform),
                _kv('OS Version', st.osVersion),
              ]),
              const SizedBox(height: 16),
              _card('Connection', [
                _kvWithIndicator('Network', st.networkConnected,
                    onlineText: 'Online', offlineText: 'Offline'),
                if (!st.networkConnected && (st.lastPollError ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(st.lastPollError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12)),
                  ),
                _kvWithIndicator('WebSocket', st.wsConnected,
                    onlineText: 'Connected', offlineText: 'Disconnected'),
                if (!st.wsConnected && (st.lastWsError ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(st.lastWsError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 16),
              _card('Printer', [
                _kvWithIndicator('Connected', st.printer.connected,
                    onlineText: 'Ready', offlineText: 'Not connected'),
                _kv('Name', st.config.printerName ?? '—'),
                _kv('Address', st.config.printerAddress ?? '—'),
                if ((st.printer.error ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Error: ${st.printer.error}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _connectPrinter(context, ref),
                      icon: const Icon(Icons.bluetooth),
                      label: const Text('Connect Printer'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _runTestPrint(context, testPrint),
                      icon: const Icon(Icons.print),
                      label: const Text('Test Print'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _forcePoll(context, ctrl),
                      icon: const Icon(Icons.sync),
                      label: const Text('Force Poll'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/tools'),
                      icon: const Icon(Icons.build),
                      label: const Text('Tools & Logs'),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 16),
              _card('Queue', [
                _kv('Pending', st.pendingCount.toString()),
                _kv('Printing', printingCount.toString()),
                _kv('Awaiting ACK', awaitingAckCount.toString()),
                _kv('Success', st.successCount.toString()),
                _kv('Failed', st.failedCount.toString()),
                _kv('Last Job', lastJobTime?.toIso8601String() ?? '—'),
              ]),
              if ((st.lastError ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                _card('Last Error', [
                  Text(
                    () {
                      final msg = st.lastError!.trim();
                      return msg.length > 120
                          ? '${msg.substring(0, 120)}…'
                          : msg;
                    }(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13),
                  )
                ]),
              ],
              // Task 2.6: Dead letter warning — navigates to /dead-letter when count > 3
              _DeadLetterWarning(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 120,
                child: Text(k,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Widget _kvWithIndicator(String k, bool connected,
          {String onlineText = 'Connected',
          String offlineText = 'Disconnected'}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 120,
                child: Text(k,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Builder(
              builder: (ctx) => Icon(
                connected ? Icons.check_circle : Icons.cancel,
                color: connected
                    ? Theme.of(ctx).colorScheme.tertiary
                    : Theme.of(ctx).colorScheme.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Text(connected ? onlineText : offlineText),
          ],
        ),
      );

  Widget _card(String title, List<Widget> children) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Future<void> _connectPrinter(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(appControllerProvider.notifier);
    final cfg = ref.read(appControllerProvider).config;
    final address = cfg.printerAddress;

    if (address == null || address.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Select a printer in Settings first')));
      }
      return;
    }

    await ctrl.connectPrinterByAddress(address, name: cfg.printerName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer connect attempted')));
    }
  }

  Future<void> _forcePoll(BuildContext context, AppController ctrl) async {
    await ctrl.forcePoll();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Polling triggered')));
    }
  }

  Future<void> _runTestPrint(BuildContext context, TestPrintService svc) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await svc.printTest();

    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green : Colors.red),
      );
    }
  }
}

/// Warning banner shown on Status screen when dead-letter queue has > 3 items.
class _DeadLetterWarning extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ref.read(appControllerProvider.notifier).getDeadLetterJobs(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count <= 3) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InkWell(
            onTap: () => context.push('/dead-letter'),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$count jobs in dead-letter queue — tap to review',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
