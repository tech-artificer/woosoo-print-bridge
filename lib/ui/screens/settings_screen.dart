import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/test_print_service.dart';
import '../../state/app_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController apiCtl;
  late TextEditingController wsCtl;
  late TextEditingController printerIdCtl;

  @override
  void initState() {
    super.initState();
    final st = ref.read(appControllerProvider);
    apiCtl = TextEditingController(text: st.config.apiBaseUrl);
    wsCtl = TextEditingController(text: st.config.wsUrl);
    printerIdCtl = TextEditingController(text: st.config.printerId);
  }

  @override
  void dispose() {
    apiCtl.dispose();
    wsCtl.dispose();
    printerIdCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final testPrint = ref.read(testPrintServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await ctrl.updateConfig(st.config.copyWith(
                apiBaseUrl: apiCtl.text.trim(),
                wsUrl: wsCtl.text.trim(),
                printerId: printerIdCtl.text.trim().isEmpty ? st.config.printerId : printerIdCtl.text.trim(),
              ));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section('Backend', [
            TextField(controller: apiCtl, decoration: const InputDecoration(labelText: 'API Base URL')),
            TextField(controller: wsCtl, decoration: const InputDecoration(labelText: 'WS URL')),
            TextField(controller: printerIdCtl, decoration: const InputDecoration(labelText: 'Printer ID (backend)')),
            const SizedBox(height: 8),
            Text('Device ID: ${st.config.deviceId ?? '—'}'),
            Text('Auth token: ${st.config.authToken == null ? '—' : '(saved)'}'),
          ]),
          const SizedBox(height: 12),
          _section('Bluetooth Printer (PB-58H)', [
            Text('Selected: ${st.config.printerName ?? '—'}'),
            Text('Address: ${st.config.printerAddress ?? '—'}'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _choosePrinter(context, ctrl),
              icon: const Icon(Icons.search),
              label: const Text('Choose from paired devices'),
            ),
            OutlinedButton.icon(
              onPressed: () => ctrl.disconnectPrinter(),
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
            ),
          ]),
          const SizedBox(height: 12),
          _section('Maintenance', [
            ElevatedButton.icon(
              onPressed: () => _runTestPrint(context, testPrint),
              icon: const Icon(Icons.print),
              label: const Text('Test Print'),
            ),
            OutlinedButton.icon(onPressed: () => context.push('/logs'), icon: const Icon(Icons.description), label: const Text('View Logs')),
            OutlinedButton.icon(onPressed: () => context.push('/queue'), icon: const Icon(Icons.list), label: const Text('View Queue')),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Future<void> _choosePrinter(BuildContext context, AppController ctrl) async {
    final printer = ref.read(printerServiceProvider);
    final list = await printer.bondedDevices();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: [
          const ListTile(
            title: Text('Paired devices'),
            subtitle: Text('Pair PB-58H in Android Bluetooth settings first (PIN 0000).'),
          ),
          for (final d in list)
            ListTile(
              title: Text(d['name'] ?? '(no name)'),
              subtitle: Text(d['address'] ?? ''),
              onTap: () async {
                Navigator.pop(context);
                await ctrl.connectPrinterByAddress(d['address']!, name: d['name']);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _runTestPrint(BuildContext context, TestPrintService svc) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await svc.printTest();

    if (mounted) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: result.success ? Colors.green : Colors.red),
      );
    }
  }
}
