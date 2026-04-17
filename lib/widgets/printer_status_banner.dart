import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';

/// Global banner displayed on all screens when the printer is disconnected.
/// Disappears automatically once the printer reconnects.
/// Mount this above the screen body (e.g. via AppShell or each screen's Column).
class PrinterStatusBanner extends ConsumerWidget {
  const PrinterStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appControllerProvider);

    if (st.printer.connected) return const SizedBox.shrink();

    final pendingCount = st.pendingCount;
    final hasAddress = (st.config.printerAddress ?? '').isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Container(
        color: Theme.of(context).colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.print_disabled, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pendingCount > 0
                    ? 'PRINTER DISCONNECTED — $pendingCount job(s) waiting'
                    : 'PRINTER DISCONNECTED',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasAddress)
              TextButton(
                onPressed: () async {
                  final ctrl = ref.read(appControllerProvider.notifier);
                  final cfg = ref.read(appControllerProvider).config;
                  await ctrl.connectPrinterByAddress(
                    cfg.printerAddress!,
                    name: cfg.printerName,
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Reconnect'),
              ),
          ],
        ),
      ),
    );
  }
}
