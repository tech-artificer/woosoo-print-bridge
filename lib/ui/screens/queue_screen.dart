import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/print_job.dart';
import '../helpers/printer_ui_rules.dart';
import '../../state/app_controller.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  PrintJobStatus? filter;
  bool _resuming = false;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final jobs = filter == null
        ? st.queue
        : st.queue.where((j) => j.status == filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Queue (${jobs.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Clear queue',
            onPressed: () => _confirmClearQueue(context, ctrl),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null),
              ),
              ChoiceChip(
                label: const Text('Pending'),
                selected: filter == PrintJobStatus.pending,
                onSelected: (_) =>
                    setState(() => filter = PrintJobStatus.pending),
              ),
              ChoiceChip(
                label: const Text('Printing'),
                selected: filter == PrintJobStatus.printing,
                onSelected: (_) =>
                    setState(() => filter = PrintJobStatus.printing),
              ),
              ChoiceChip(
                label: const Text('Awaiting ACK'),
                selected: filter == PrintJobStatus.printedAwaitingAck,
                onSelected: (_) => setState(
                    () => filter = PrintJobStatus.printedAwaitingAck),
              ),
              ChoiceChip(
                label: const Text('Success'),
                selected: filter == PrintJobStatus.success,
                onSelected: (_) =>
                    setState(() => filter = PrintJobStatus.success),
              ),
              ChoiceChip(
                label: const Text('Failed'),
                selected: filter == PrintJobStatus.failed,
                onSelected: (_) =>
                    setState(() => filter = PrintJobStatus.failed),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (st.pendingCount > 0 &&
              printerQueueReasonIsBlocking(
                st.lastQueueSkipReason,
                st.config.strictStatusRequired,
              )) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.block,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Blocked: ${st.lastQueueSkipReason}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (st.queuePaused) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.report_problem,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        st.queuePauseReason ??
                            'Queue paused. Check printer and resume.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: _resuming
                          ? null
                          : () async {
                              setState(() => _resuming = true);
                              try {
                                await ctrl.resumeAndProcessPending();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Resume failed: $e')),
                                );
                              } finally {
                                if (mounted) setState(() => _resuming = false);
                              }
                            },
                      child: _resuming
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Resume and process pending'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (jobs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No jobs'),
              ),
            ),
          for (final j in jobs) _jobCard(context, j, ctrl),
          const SizedBox(height: 20),
          _deadLetterSection(context, ctrl),
        ],
      ),
    );
  }

  Future<void> _confirmClearQueue(
      BuildContext context, AppController ctrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear queue?'),
        content: const Text(
            'This removes all visible queued jobs from this device. Use this only after confirming no pending print is needed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ctrl.clearQueue();
  }

  Widget _deadLetterSection(BuildContext context, AppController ctrl) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ctrl.getDeadLetterJobs(),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dead Letter Queue (${rows.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      tooltip: 'Refresh dead-letter list',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() {}),
                    ),
                  ],
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No dead-letter jobs.'),
                  )
                else
                  ...rows.map((row) {
                    final id = row['printEventId'];
                    final orderId = row['orderId'];
                    final reason =
                        row['dead_letter_reason']?.toString() ?? 'unknown';
                    final failedAt = row['failed_at']?.toString() ?? 'n/a';

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      title: Text('Job #$id - Order #$orderId'),
                      subtitle: Text('Reason: $reason\nFailed at: $failedAt'),
                      trailing: IconButton(
                        tooltip: 'Requeue this dead-letter job',
                        icon: const Icon(Icons.replay),
                        onPressed: () async {
                          if (id is! int) return;
                          await ctrl.retryDeadLetterJob(id);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _jobCard(BuildContext context, PrintJob j, AppController ctrl) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(context, j.status);
    final isRefill = j.printType.toUpperCase() == 'REFILL';
    final tableName =
        (j.payload['tablename'] ?? j.payload['table_name'] ?? 'No table')
            .toString();
    final orderNumber =
        (j.payload['order_number'] ?? j.payload['orderNumber'] ?? j.orderId)
            .toString();
    final items = (j.payload['items'] as List?) ?? const [];
    final itemPreview = _itemPreview(j);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.circle, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Table $tableName',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      _badge(
                        isRefill
                            ? 'REFILL${j.refillNumber != null ? ' #${j.refillNumber}' : ''}'
                            : 'INITIAL',
                        isRefill ? cs.error : cs.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Order #$orderNumber - ${items.length} item(s)'),
                  if (itemPreview.isNotEmpty)
                    Text(
                      itemPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${_prettyStatus(j.status)} - Job #${j.printEventId} - Retries: ${j.retryCount}',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  if (j.lastError != null)
                    Text(
                      j.lastError!,
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: j.status == PrintJobStatus.success
                      ? 'Reprint without ACK'
                      : 'Print now',
                  icon: const Icon(Icons.print),
                  onPressed: () => _handleManualPrint(context, j, ctrl),
                ),
                if (j.status == PrintJobStatus.failed)
                  IconButton(
                    tooltip: 'Retry',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ctrl.retryJob(j.printEventId),
                  ),
                if (j.status == PrintJobStatus.pending)
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.cancel),
                    onPressed: () => ctrl.cancelJob(j.printEventId),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleManualPrint(
    BuildContext context,
    PrintJob job,
    AppController ctrl,
  ) async {
    final isReprint = job.status == PrintJobStatus.success;
    try {
      if (isReprint) {
        await ctrl.reprintOrder(job);
      } else {
        await ctrl.forcePrintJob(job.printEventId);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isReprint
              ? 'Order #${job.orderId} reprinted without ACK'
              : 'Job #${job.printEventId} printed and ACK queued'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Manual print failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Color _statusColor(BuildContext context, PrintJobStatus status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case PrintJobStatus.pending:
        return cs.secondary;
      case PrintJobStatus.printing:
        return cs.primary;
      case PrintJobStatus.printedAwaitingAck:
        return cs.primaryContainer;
      case PrintJobStatus.success:
        return cs.tertiary;
      case PrintJobStatus.failed:
        return cs.error;
      case PrintJobStatus.cancelled:
        return cs.outline;
    }
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(45),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  String _prettyStatus(PrintJobStatus status) {
    return status.name
        .split('_')
        .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }

  String _itemPreview(PrintJob job) {
    final rawItems = (job.payload['items'] as List?) ?? const [];
    final isRefill = job.printType.toUpperCase() == 'REFILL';
    final visibleItems = isRefill
        ? rawItems
        : (rawItems.length > 1 ? rawItems.sublist(1) : rawItems);
    final names = visibleItems.take(3).map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final qty = map['quantity'] ?? 1;
      final name = (map['name'] ?? 'Unnamed item').toString();
      return '${qty}x $name';
    }).toList();
    final extra = visibleItems.length > names.length
        ? ' +${visibleItems.length - names.length} more'
        : '';
    return '${names.join(', ')}$extra';
  }
}
