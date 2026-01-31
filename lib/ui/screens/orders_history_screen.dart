import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/print_job.dart';
import '../../state/app_controller.dart';

class OrdersHistoryScreen extends ConsumerStatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  ConsumerState<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends ConsumerState<OrdersHistoryScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, success, failed, pending

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);

    // Get all jobs and filter
    var filteredJobs = st.queue.where((job) {
      // Apply status filter
      if (_filterStatus != 'all') {
        if (_filterStatus == 'success' && job.status != PrintJobStatus.success) return false;
        if (_filterStatus == 'failed' && job.status != PrintJobStatus.failed) return false;
        if (_filterStatus == 'pending' && job.status != PrintJobStatus.pending && job.status != PrintJobStatus.printing) return false;
      }

      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final orderIdMatch = job.orderId.toString().contains(query);
        final printTypeMatch = job.printType.toLowerCase().contains(query);
        final tableName = (job.payload['tablename'] ?? job.payload['table_name'] ?? '').toString().toLowerCase();
        final tableMatch = tableName.contains(query);
        
        return orderIdMatch || printTypeMatch || tableMatch;
      }

      return true;
    }).toList();

    // Sort by most recent first
    filteredJobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ctrl.forcePoll(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by order ID, table, or type...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', 'all'),
                      const SizedBox(width: 8),
                      _filterChip('Success', 'success'),
                      const SizedBox(width: 8),
                      _filterChip('Failed', 'failed'),
                      const SizedBox(width: 8),
                      _filterChip('Pending', 'pending'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Table Header
          Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 2, child: _headerText('Table')),
                Expanded(flex: 2, child: _headerText('Order ID')),
                Expanded(flex: 2, child: _headerText('Type')),
                Expanded(flex: 1, child: _headerText('Status')),
                Expanded(flex: 2, child: _headerText('Time')),
                Expanded(flex: 1, child: _headerText('Actions')),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: filteredJobs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _filterStatus != 'all'
                              ? 'No orders match your filters'
                              : 'No orders yet',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredJobs.length,
                    itemBuilder: (context, index) {
                      final job = filteredJobs[index];
                      return _OrderRow(job: job, onReprint: () => _handleReprint(context, job, ctrl));
                    },
                  ),
          ),

          // Summary Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem('Total', filteredJobs.length, Colors.blue),
                _summaryItem('Success', filteredJobs.where((j) => j.status == PrintJobStatus.success).length, Colors.green),
                _summaryItem('Failed', filteredJobs.where((j) => j.status == PrintJobStatus.failed).length, Colors.red),
                _summaryItem('Pending', filteredJobs.where((j) => j.status == PrintJobStatus.pending || j.status == PrintJobStatus.printing).length, Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => setState(() => _filterStatus = value),
      selectedColor: Colors.blue.shade100,
    );
  }

  Widget _headerText(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
    );
  }

  Widget _summaryItem(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count.toString(),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Future<void> _handleReprint(BuildContext context, PrintJob job, AppController ctrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reprint Order'),
        content: Text('Reprint order #${job.orderId}?\n\nThis will send the order to the printer again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reprint')),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ctrl.reprintOrder(job);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order #${job.orderId} queued for reprinting')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reprint failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

class _OrderRow extends StatelessWidget {
  final PrintJob job;
  final VoidCallback onReprint;

  const _OrderRow({required this.job, required this.onReprint});

  @override
  Widget build(BuildContext context) {
    final tableName = (job.payload['tablename'] ?? job.payload['table_name'] ?? '—').toString();
    final statusIcon = _getStatusIcon(job.status);
    final statusColor = _getStatusColor(job.status);
    final time = _formatTime(job.createdAt);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(context, job),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  tableName,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '#${job.orderId}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  job.printType,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                flex: 1,
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  time,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              Expanded(
                flex: 1,
                child: IconButton(
                  icon: const Icon(Icons.print, size: 20),
                  onPressed: onReprint,
                  tooltip: 'Reprint',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getStatusIcon(PrintJobStatus status) {
    switch (status) {
      case PrintJobStatus.success:
        return Icons.check_circle;
      case PrintJobStatus.failed:
      case PrintJobStatus.cancelled:
        return Icons.cancel;
      case PrintJobStatus.printing:
      case PrintJobStatus.printed_awaiting_ack:
        return Icons.sync;
      case PrintJobStatus.pending:
        return Icons.schedule;
    }
  }

  Color _getStatusColor(PrintJobStatus status) {
    switch (status) {
      case PrintJobStatus.success:
        return Colors.green;
      case PrintJobStatus.failed:
      case PrintJobStatus.cancelled:
        return Colors.red;
      case PrintJobStatus.printing:
      case PrintJobStatus.printed_awaiting_ack:
        return Colors.blue;
      case PrintJobStatus.pending:
        return Colors.orange;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showOrderDetails(BuildContext context, PrintJob job) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Order #${job.orderId}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Print Event ID', job.printEventId.toString()),
              _detailRow('Order ID', job.orderId.toString()),
              _detailRow('Session ID', job.sessionId?.toString() ?? '—'),
              _detailRow('Print Type', job.printType),
              _detailRow('Status', job.status.name.toUpperCase()),
              _detailRow('Table', (job.payload['tablename'] ?? job.payload['table_name'] ?? '—').toString()),
              _detailRow('Order Number', (job.payload['order_number'] ?? job.payload['orderNumber'] ?? '—').toString()),
              _detailRow('Created', job.createdAt.toIso8601String()),
              if (job.printedAt != null) _detailRow('Printed', job.printedAt!.toIso8601String()),
              if (job.retryCount > 0) _detailRow('Retry Count', job.retryCount.toString()),
              if (job.lastError != null) ...[
                const SizedBox(height: 8),
                const Text('Error:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                Text(job.lastError!, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
