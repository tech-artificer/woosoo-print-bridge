import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/print_job.dart';
import '../../state/app_controller.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  PrintJobStatus? filter;

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
              onPressed: () => ctrl.clearQueue())
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                  label: const Text('All'),
                  selected: filter == null,
                  onSelected: (_) => setState(() => filter = null)),
              ChoiceChip(
                  label: const Text('Pending'),
                  selected: filter == PrintJobStatus.pending,
                  onSelected: (_) =>
                      setState(() => filter = PrintJobStatus.pending)),
              ChoiceChip(
                  label: const Text('Printing'),
                  selected: filter == PrintJobStatus.printing,
                  onSelected: (_) =>
                      setState(() => filter = PrintJobStatus.printing)),
              ChoiceChip(
                  label: const Text('Success'),
                  selected: filter == PrintJobStatus.success,
                  onSelected: (_) =>
                      setState(() => filter = PrintJobStatus.success)),
              ChoiceChip(
                  label: const Text('Failed'),
                  selected: filter == PrintJobStatus.failed,
                  onSelected: (_) =>
                      setState(() => filter = PrintJobStatus.failed)),
            ],
          ),
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(32), child: Text('No jobs'))),
          for (final j in jobs) _jobCard(context, j, ctrl),
          const SizedBox(height: 20),
          _deadLetterSection(context, ctrl),
        ],
      ),
    );
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
                    )
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
                      title: Text('Job #$id • Order #$orderId'),
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
    Color? color;
    switch (j.status) {
      case PrintJobStatus.pending:
        color = cs.secondary;
        break;
      case PrintJobStatus.printing:
        color = cs.primary;
        break;
      case PrintJobStatus.printed_awaiting_ack:
        color = cs.primaryContainer;
        break;
      case PrintJobStatus.success:
        color = cs.tertiary;
        break;
      case PrintJobStatus.failed:
        color = cs.error;
        break;
      case PrintJobStatus.cancelled:
        color = cs.outline;
        break;
    }

    return Card(
      child: ListTile(
        title: Text('Job #${j.printEventId} • Order #${j.orderId}'),
        subtitle: Text(
            '${j.printType}${j.refillNumber != null ? ' #${j.refillNumber}' : ''} • Retries: ${j.retryCount}${j.lastError != null ? '\n${j.lastError}' : ''}'),
        leading: Icon(Icons.circle, color: color),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (j.status == PrintJobStatus.failed)
              IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ctrl.retryJob(j.printEventId)),
            if (j.status == PrintJobStatus.pending)
              IconButton(
                  icon: const Icon(Icons.cancel),
                  onPressed: () => ctrl.cancelJob(j.printEventId)),
          ],
        ),
      ),
    );
  }
}
