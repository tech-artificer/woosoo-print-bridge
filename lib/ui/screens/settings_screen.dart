import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../services/test_print_service.dart';
import '../../state/app_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiCtl;
  late TextEditingController _appKeyCtl;
  late TextEditingController _printerIdCtl;

  // Derived WS URL — shown read-only, auto-updated as user types
  String _derivedWsUrl = '';

  // Registration
  final _regNameCtl = TextEditingController(text: 'Kitchen Relay');
  final _regCodeCtl = TextEditingController();
  bool _registering = false;
  String? _regResult;
  bool _regSuccess = false;

  @override
  void initState() {
    super.initState();
    final st = ref.read(appControllerProvider);
    _apiCtl    = TextEditingController(text: st.config.apiBaseUrl);
    _appKeyCtl = TextEditingController(text: st.config.reverbAppKey);
    _printerIdCtl = TextEditingController(text: st.config.printerId);
    _derivedWsUrl = AppConstants.deriveWsUrl(st.config.apiBaseUrl, appKey: st.config.reverbAppKey);

    // Keep derived WS URL label in sync as user edits
    _apiCtl.addListener(_onUrlChanged);
    _appKeyCtl.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final ws = AppConstants.deriveWsUrl(_apiCtl.text.trim(), appKey: _appKeyCtl.text.trim());
    if (ws != _derivedWsUrl) setState(() => _derivedWsUrl = ws);
  }

  @override
  void dispose() {
    _apiCtl.removeListener(_onUrlChanged);
    _appKeyCtl.removeListener(_onUrlChanged);
    _apiCtl.dispose();
    _appKeyCtl.dispose();
    _printerIdCtl.dispose();
    _regNameCtl.dispose();
    _regCodeCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final testPrint = ref.read(testPrintServiceProvider);

    final isRegistered = (st.config.deviceId ?? '').isNotEmpty &&
        (st.config.authToken ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _saveBackend(ctrl, context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── Backend ─────────────────────────────────────────────────────
          _section('Backend', [
            TextField(
              controller: _apiCtl,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'https://192.168.100.7:8443',
              ),
              autocorrect: false,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _appKeyCtl,
              decoration: const InputDecoration(
                labelText: 'Reverb App Key',
                hintText: 'From woosoo-nexus REVERB_APP_KEY',
              ),
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 8),
            // Auto-derived WS URL — read-only preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('WebSocket URL (auto-derived)', style: TextStyle(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 2),
                Text(_derivedWsUrl, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _printerIdCtl,
              decoration: const InputDecoration(labelText: 'Printer ID (backend)'),
            ),
            const SizedBox(height: 8),
            Text('Device ID: ${st.config.deviceId ?? '—'}', style: const TextStyle(fontSize: 12)),
            Text('Auth token: ${st.config.authToken == null ? '—' : '(saved)'}', style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 12),

          // ── Device Registration ─────────────────────────────────────────
          _section('Device Registration', [
            if (isRegistered)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Registered — ID: ${st.config.deviceId}',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            TextField(
              controller: _regNameCtl,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                hintText: 'e.g. Kitchen Relay',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _regCodeCtl,
              decoration: const InputDecoration(
                labelText: 'Registration Code',
                hintText: 'Enter code from admin panel',
              ),
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 10),
            if (_regResult != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _regSuccess ? Colors.green.shade900 : Colors.red.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _regResult!,
                  style: TextStyle(
                    color: _regSuccess ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _registering ? null : () => _doRegister(ctrl),
              icon: _registering
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.app_registration),
              label: Text(_registering
                  ? 'Registering…'
                  : (isRegistered ? 'Re-register' : 'Register Device')),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Bluetooth Printer ───────────────────────────────────────────
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

          // ── Maintenance ─────────────────────────────────────────────────
          _section('Maintenance', [
            ElevatedButton.icon(
              onPressed: () => _runTestPrint(context, testPrint),
              icon: const Icon(Icons.print),
              label: const Text('Test Print'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/logs'),
              icon: const Icon(Icons.description),
              label: const Text('View Logs'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/queue'),
              icon: const Icon(Icons.list),
              label: const Text('View Queue'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _saveBackend(AppController ctrl, BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final api  = _apiCtl.text.trim();
    final key  = _appKeyCtl.text.trim();
    final wsUrl = AppConstants.deriveWsUrl(api, appKey: key);
    await ctrl.updateConfig(ref.read(appControllerProvider).config.copyWith(
      apiBaseUrl:    api,
      wsUrl:         wsUrl,
      reverbAppKey:  key,
      printerId:     _printerIdCtl.text.trim().isNotEmpty ? _printerIdCtl.text.trim() : null,
    ));
    messenger.showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _doRegister(AppController ctrl) async {
    final name = _regNameCtl.text.trim();
    final code = _regCodeCtl.text.trim();
    if (name.isEmpty || code.isEmpty) {
      setState(() { _regResult = 'Name and code are required.'; _regSuccess = false; });
      return;
    }
    setState(() { _registering = true; _regResult = null; });
    final error = await ctrl.registerDevice(name: name, code: code);
    if (!mounted) return;
    setState(() {
      _registering = false;
      _regSuccess  = error == null;
      _regResult   = error ?? '✓ Registered successfully!';
      if (error == null) _regCodeCtl.clear();
    });
  }

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Future<void> _choosePrinter(BuildContext _, AppController ctrl) async {
    final printer = ref.read(printerServiceProvider);
    final list    = await printer.bondedDevices();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context, // State.context — safe after mounted check
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
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await svc.printTest();
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }
}
