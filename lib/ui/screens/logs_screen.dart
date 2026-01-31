import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_controller.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String text = '';
  bool loading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => loading = true);
    final path = ref.read(loggerProvider).logPath;
    if (path == null) {
      setState(() { text = 'No log file yet.'; loading = false; });
      return;
    }
    try { 
      final rawText = await File(path).readAsString();
      // Reverse log lines so latest appears first
      final lines = rawText.split('\n');
      text = lines.reversed.join('\n');
    }
    catch (e) { text = 'Failed to read log file: $e'; }
    setState(() => loading = false);
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs?'),
        content: const Text('This will delete all log history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;

    final path = ref.read(loggerProvider).logPath;
    if (path != null) {
      try {
        await File(path).writeAsString('');
        await _load();
      } catch (e) {
        setState(() => text = 'Failed to clear log: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear, tooltip: 'Clear logs'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(padding: const EdgeInsets.all(12), child: SelectableText(text.isEmpty ? '(empty)' : text)),
    );
  }
}
