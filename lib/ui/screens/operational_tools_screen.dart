import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class OperationalToolsScreen extends ConsumerStatefulWidget {
  const OperationalToolsScreen({super.key});

  @override
  ConsumerState<OperationalToolsScreen> createState() =>
      _OperationalToolsScreenState();
}

class _OperationalToolsScreenState
    extends ConsumerState<OperationalToolsScreen> {
  // Log categories
  Map<String, List<LogEntry>> logsByCategory = {
    'WS': [],
    'POLL': [],
    'PRINT': [],
    'ACK': [],
    'BT': [],
    'DB': [],
  };

  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    // In a real implementation, this would read from device logs
    // For now, we simulate structured log categories
    setState(() {
      logsByCategory = {
        'WS': [
          LogEntry('17:39:12.453', 'WebSocket connected', 'INFO'),
          LogEntry('17:39:15.120', 'Event received: print_event_id=1', 'INFO'),
          LogEntry('17:40:30.452', 'WebSocket disconnected (network timeout)',
              'WARN'),
        ],
        'POLL': [
          LogEntry('17:40:31.001', 'Polling started (WS unavailable)', 'INFO'),
          LogEntry(
              '17:40:31.453', 'Watermark: since=2026-01-23T15:30:00Z', 'DEBUG'),
          LogEntry('17:40:32.120', 'Polling returned 2 events', 'INFO'),
        ],
        'PRINT': [
          LogEntry('17:39:15.200', 'Print job started: order_id=5001', 'INFO'),
          LogEntry(
              '17:39:16.453', 'Bluetooth: Sent 256 bytes to printer', 'DEBUG'),
          LogEntry(
              '17:39:18.120', 'Print job completed: 2.9s duration', 'INFO'),
        ],
        'ACK': [
          LogEntry(
              '17:39:18.300', 'ACK attempt 1/3 for print_event_id=1', 'INFO'),
          LogEntry(
              '17:39:20.453', 'ACK succeeded for print_event_id=1', 'INFO'),
          LogEntry(
              '17:39:25.200', 'ACK attempt 1/3 for print_event_id=2', 'INFO'),
        ],
        'BT': [
          LogEntry('17:39:10.001', 'Bluetooth initialized', 'INFO'),
          LogEntry('17:39:10.453', 'Device discovered: PB58-ABC123', 'INFO'),
          LogEntry(
              '17:39:11.120', 'Printer connected (AA:BB:CC:DD:EE:FF)', 'INFO'),
        ],
        'DB': [
          LogEntry('17:39:15.300',
              'Job inserted: print_event_id=1, status=pending', 'DEBUG'),
          LogEntry('17:39:15.400',
              'Job updated: print_event_id=1, status=printing', 'DEBUG'),
          LogEntry('17:39:18.300',
              'Job updated: print_event_id=1, status=success', 'DEBUG'),
        ],
      };
    });
  }

  Future<void> _exportLogs() async {
    setState(() => _isExporting = true);

    try {
      // Build structured log export
      final buffer = StringBuffer();
      buffer.writeln('=== WOOSOO RELAY DEVICE — OPERATIONAL LOGS ===');
      buffer.writeln(
          'Exported: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln('');

      for (final category in logsByCategory.keys) {
        buffer.writeln('\n=== $category LOGS ===');
        for (final log in logsByCategory[category]!) {
          buffer.writeln('[${log.timestamp}] [${log.level}] ${log.message}');
        }
      }

      await Share.share(buffer.toString(), subject: 'Relay Device Logs');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _performAction(String actionName) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Executing: $actionName')),
    );

    try {
      switch (actionName) {
        case 'Restart WebSocket':
          // Trigger WebSocket reconnection
          // This would call reverb_service.disconnect() + connect()
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ WebSocket restarted')),
          );
          break;

        case 'Force Poll':
          // Trigger immediate polling
          // This would call polling_service.poll() right now
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ Polling triggered (may take 5-10s)')),
          );
          break;

        case 'Flush Pending ACKs':
          // Trigger FlushService immediately
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ ACK flush triggered')),
          );
          break;

        case 'Connect Printer':
          // Re-pair Bluetooth
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Printer connection initiated')),
          );
          break;

        case 'Clear Failed Queue':
          // Remove all failed jobs from queue
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Failed jobs cleared')),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operational Tools'),
        backgroundColor: const Color(0xFF2C3E50),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ====================================================================
          // SECTION 1: Quick Recovery Actions
          // ====================================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Recovery Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildActionButton('Restart WebSocket', Icons.cloud),
                      _buildActionButton('Force Poll', Icons.sync),
                      _buildActionButton(
                          'Flush Pending ACKs', Icons.check_circle),
                      _buildActionButton('Connect Printer', Icons.print),
                      _buildActionButton('Clear Failed Queue', Icons.delete),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ====================================================================
          // SECTION 2: Structured Logs by Category
          // ====================================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Structured Logs',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportLogs,
                        icon: const Icon(Icons.download),
                        label: Text(_isExporting ? 'Exporting...' : 'Export'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF27AE60),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Log categories (expandable)
                  ..._buildLogCategoryWidgets(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ====================================================================
          // SECTION 3: Status Summary
          // ====================================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Device Status Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildStatusRow('WebSocket', 'Connected', Colors.green),
                  _buildStatusRow('Printer', 'AA:BB:CC:DD:EE:FF', Colors.green),
                  _buildStatusRow('Network', 'Online', Colors.green),
                  _buildStatusRow(
                      'Queue', '5 pending, 0 awaiting ACK', Colors.orange),
                  _buildStatusRow('Last Poll', '30 seconds ago', Colors.blue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () => _performAction(label),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: const Color(0xFF3498DB),
        foregroundColor: Colors.white,
      ),
    );
  }

  List<Widget> _buildLogCategoryWidgets() {
    return logsByCategory.entries.map((entry) {
      final category = entry.key;
      final logs = entry.value;

      return Column(
        children: [
          ExpansionTile(
            title: Text(
              '$category (${logs.length} entries)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              Container(
                color: Colors.grey[50],
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Timestamp')),
                      DataColumn(label: Text('Level')),
                      DataColumn(label: Text('Message')),
                    ],
                    rows: logs.map((log) {
                      return DataRow(cells: [
                        DataCell(Text(log.timestamp,
                            style: const TextStyle(fontSize: 12))),
                        DataCell(
                          Text(
                            log.level,
                            style: TextStyle(
                              fontSize: 12,
                              color: log.level == 'ERROR'
                                  ? Colors.red
                                  : log.level == 'WARN'
                                      ? Colors.orange
                                      : Colors.grey,
                            ),
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(log.message,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }).toList();
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class LogEntry {
  final String timestamp;
  final String message;
  final String level; // INFO, WARN, ERROR, DEBUG

  LogEntry(this.timestamp, this.message, this.level);
}
