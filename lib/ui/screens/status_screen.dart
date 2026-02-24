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
        actions: [
          IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => context.push('/orders')),
          IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: () => context.push('/metrics')),
          IconButton(
              icon: const Icon(Icons.list),
              onPressed: () => context.push('/queue')),
          IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => context.push('/settings')),
        ],
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
              ]),
              const SizedBox(height: 12),
              _card('Connection', [
                _kvWithIndicator('Network', st.networkConnected,
                    onlineText: 'Online', offlineText: 'Offline'),
                if (!st.networkConnected && (st.lastPollError ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(st.lastPollError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                _kvWithIndicator('WebSocket', st.wsConnected,
                    onlineText: 'Connected', offlineText: 'Disconnected'),
                if (!st.wsConnected && (st.lastWsError ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(st.lastWsError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 12),
              _card('Printer', [
                _kvWithIndicator('Connected', st.printer.connected,
                    onlineText: 'Ready', offlineText: 'Not connected'),
                _kv('Name', st.config.printerName ?? '—'),
                _kv('Address', st.config.printerAddress ?? '—'),
                if ((st.printer.error ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Error: ${st.printer.error}',
                        style: const TextStyle(color: Colors.red)),
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
              const SizedBox(height: 12),
              _card('Queue', [
                _kv('Pending', st.pendingCount.toString()),
                _kv('Printing', printingCount.toString()),
                _kv('Awaiting ACK', awaitingAckCount.toString()),
                _kv('Success', st.successCount.toString()),
                _kv('Failed', st.failedCount.toString()),
                _kv('Last Job', lastJobTime?.toIso8601String() ?? '—'),
              ]),
              if ((st.lastError ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _card('Last Error', [
                  Text(st.lastError!, style: const TextStyle(color: Colors.red))
                ]),
              ],
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
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
