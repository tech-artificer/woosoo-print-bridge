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
  bool _strictStatusRequired = false;

  // Derived WS URL — shown read-only, auto-updated as user types
  String _derivedWsUrl = '';

  // Registration
  late TextEditingController _regCodeCtl;
  bool _registering = false;
  String? _regResult;
  bool _regSuccess = false;

  String _maskSensitive(String? value, {int keepStart = 3, int keepEnd = 3}) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '—';
    if (raw.length <= (keepStart + keepEnd)) return '***';

    final start = raw.substring(0, keepStart);
    final end = raw.substring(raw.length - keepEnd);
    return '$start***$end';
  }

  @override
  void initState() {
    super.initState();
    final st = ref.read(appControllerProvider);
    _apiCtl    = TextEditingController(text: st.config.apiBaseUrl);
    _appKeyCtl = TextEditingController(text: st.config.reverbAppKey);
    _printerIdCtl = TextEditingController(text: st.config.printerId);
    _regCodeCtl = TextEditingController(text: st.config.registrationCode ?? '');
    _strictStatusRequired = st.config.strictStatusRequired;
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
                hintText: 'https://your-server:8443',
              ),
              autocorrect: false,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            // Reverb App Key — auto-fetched from server; shown read-only for diagnostics
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reverb App Key (auto-fetched from server)', style: TextStyle(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 2),
                Text(
                  _maskSensitive(_appKeyCtl.text, keepStart: 4, keepEnd: 4),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ]),
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Strict status verification'),
              subtitle: Text(
                _strictStatusRequired
                    ? 'Requires ESC/POS status checks before ACK.'
                    : 'Compatible mode: allows printing when status read is unsupported.',
              ),
              value: _strictStatusRequired,
              onChanged: (v) => setState(() => _strictStatusRequired = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Device ID: ${_maskSensitive(st.config.deviceId, keepStart: 3, keepEnd: 3)}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Auth token: ${_maskSensitive(st.config.authToken, keepStart: 4, keepEnd: 4)}',
              style: const TextStyle(fontSize: 12),
            ),
          ]),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // ── Device Registration ─────────────────────────────────────────
          _section('Device Registration', [
            if (isRegistered)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Icon(Icons.check_circle, color: Theme.of(context).colorScheme.tertiary, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        'Registered — ID: ${st.config.deviceId}',
                        style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontSize: 12),
                      ),
                      if ((st.config.registrationCode ?? '').isNotEmpty)
                        Text(
                          'Code: ${st.config.registrationCode}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary.withAlpha(200),
                            fontSize: 11,
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
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
                  color: _regSuccess ? Theme.of(context).colorScheme.tertiary.withAlpha(40) : Theme.of(context).colorScheme.error.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _regResult!,
                  style: TextStyle(
                    color: _regSuccess ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.error,
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
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

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
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

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
      strictStatusRequired: _strictStatusRequired,
    ));
    messenger.showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _doRegister(AppController ctrl) async {
    final code = _regCodeCtl.text.trim();
    if (code.isEmpty) {
      setState(() { _regResult = 'Registration code is required.'; _regSuccess = false; });
      return;
    }
    setState(() { _registering = true; _regResult = null; });
    final error = await ctrl.registerDevice(code: code);
    if (!mounted) return;
    setState(() {
      _registering = false;
      _regSuccess  = error == null;
      _regResult   = error ?? '✓ Registered successfully!';
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
    final successColor = Theme.of(context).colorScheme.tertiary;
    final errorColor = Theme.of(context).colorScheme.error;
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
        backgroundColor: result.success ? successColor : errorColor,
      ),
    );
  }
}
