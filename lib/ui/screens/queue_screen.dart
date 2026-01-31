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
    final jobs = filter == null ? st.queue : st.queue.where((j) => j.status == filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Queue (${jobs.length})'),
        actions: [IconButton(icon: const Icon(Icons.delete_forever), onPressed: () => ctrl.clearQueue())],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('All'), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
              ChoiceChip(label: const Text('Pending'), selected: filter == PrintJobStatus.pending, onSelected: (_) => setState(() => filter = PrintJobStatus.pending)),
              ChoiceChip(label: const Text('Printing'), selected: filter == PrintJobStatus.printing, onSelected: (_) => setState(() => filter = PrintJobStatus.printing)),
              ChoiceChip(label: const Text('Success'), selected: filter == PrintJobStatus.success, onSelected: (_) => setState(() => filter = PrintJobStatus.success)),
              ChoiceChip(label: const Text('Failed'), selected: filter == PrintJobStatus.failed, onSelected: (_) => setState(() => filter = PrintJobStatus.failed)),
            ],
          ),
          const SizedBox(height: 12),
          if (jobs.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No jobs'))),
          for (final j in jobs) _jobCard(j, ctrl),
        ],
      ),
    );
  }

  Widget _jobCard(PrintJob j, AppController ctrl) {
    Color? color;
    switch (j.status) {
      case PrintJobStatus.pending: color = Colors.orange; break;
      case PrintJobStatus.printing: color = Colors.blue; break;
      case PrintJobStatus.printed_awaiting_ack: color = Colors.lightBlue; break;
      case PrintJobStatus.success: color = Colors.green; break;
      case PrintJobStatus.failed: color = Colors.red; break;
      case PrintJobStatus.cancelled: color = Colors.grey; break;
    }

    return Card(
      child: ListTile(
        title: Text('print_event_id=${j.printEventId} • order_id=${j.orderId}'),
        subtitle: Text('${j.printType}${j.refillNumber != null ? ' #${j.refillNumber}' : ''} • retry=${j.retryCount}${j.lastError != null ? '\n${j.lastError}' : ''}'),
        leading: Icon(Icons.circle, color: color),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (j.status == PrintJobStatus.failed)
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => ctrl.retryJob(j.printEventId)),
            if (j.status == PrintJobStatus.pending)
              IconButton(icon: const Icon(Icons.cancel), onPressed: () => ctrl.cancelJob(j.printEventId)),
          ],
        ),
      ),
    );
  }
}
