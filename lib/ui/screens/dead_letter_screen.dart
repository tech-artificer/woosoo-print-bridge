import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';

class DeadLetterScreen extends ConsumerStatefulWidget {
  const DeadLetterScreen({super.key});

  @override
  ConsumerState<DeadLetterScreen> createState() => _DeadLetterScreenState();
}

class _DeadLetterScreenState extends ConsumerState<DeadLetterScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final jobs = await ref.read(appControllerProvider.notifier).getDeadLetterJobs();
    if (mounted) setState(() { _items = jobs; _loading = false; });
  }

  Future<void> _retryOne(int printEventId) async {
    await ref.read(appControllerProvider.notifier).retryDeadLetterJob(printEventId);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job requeued for retry')),
      );
    }
  }

  Future<void> _discardOne(int printEventId) async {
    final confirmed = await _confirmDiscard(context, 'Discard this failed job? This cannot be undone.');
    if (!confirmed) return;
    await ref.read(appControllerProvider.notifier).discardDeadLetterJob(printEventId);
    await _load();
  }

  Future<void> _retryAll() async {
    await ref.read(appControllerProvider.notifier).retryAllDeadLetterJobs();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All dead-letter jobs requeued')),
      );
    }
  }

  Future<void> _discardAll() async {
    final confirmed = await _confirmDiscard(context, 'Discard ALL ${_items.length} failed job(s)? This cannot be undone.');
    if (!confirmed) return;
    await ref.read(appControllerProvider.notifier).discardAllDeadLetterJobs();
    await _load();
  }

  Future<bool> _confirmDiscard(BuildContext context, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Discard'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dead Letter Queue (${_items.length})'),
        actions: [
          if (_items.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Retry All',
              onPressed: _retryAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Discard All',
              onPressed: _discardAll,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: colorScheme.primary),
                      const SizedBox(height: 12),
                      const Text('No dead-letter jobs', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final printEventId = item['printEventId'] as int? ?? 0;
                      final orderId = item['orderId']?.toString() ?? '—';
                      final reason = item['dead_letter_reason'] as String? ?? 'Unknown';
                      final failedAt = item['failed_at'] as String?;
                      final retryCount = item['retryCount']?.toString() ?? '0';

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.error_outline, size: 18, color: colorScheme.error),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Event #$printEventId · Order #$orderId',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Reason: $reason', style: const TextStyle(fontSize: 13)),
                              Text('Retries: $retryCount', style: const TextStyle(fontSize: 13)),
                              if (failedAt != null)
                                Text('Failed at: $failedAt', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _discardOne(printEventId),
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    label: const Text('Discard'),
                                    style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: () => _retryOne(printEventId),
                                    icon: const Icon(Icons.replay, size: 16),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
