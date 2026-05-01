import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../ui/helpers/printer_ui_rules.dart';

class PrinterStatusBanner extends ConsumerWidget {
  const PrinterStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appControllerProvider);
    final strictStatusRequired = st.config.strictStatusRequired;
    final hardBlocked = printerHasHardBlock(st.printer, strictStatusRequired);
    final unsupportedWarningOnly =
        printerHasCompatibleStatusWarning(st.printer, strictStatusRequired);

    if (!hardBlocked && !unsupportedWarningOnly) return const SizedBox.shrink();

    final pendingCount = st.pendingCount;
    final hasAddress = (st.config.printerAddress ?? '').isNotEmpty;
    final label = _label(st, strictStatusRequired: strictStatusRequired);
    final background = hardBlocked
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiaryContainer;
    final foreground = hardBlocked
        ? Colors.white
        : Theme.of(context).colorScheme.onTertiaryContainer;
    final icon =
        hardBlocked ? Icons.print_disabled : Icons.warning_amber_rounded;

    return Material(
      color: Colors.transparent,
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pendingCount > 0
                    ? '$label - $pendingCount job(s) waiting'
                    : label,
                style: TextStyle(
                  color: foreground,
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
                  foregroundColor: foreground,
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

  String _label(dynamic st, {required bool strictStatusRequired}) {
    if (!st.printer.connected) return 'PRINTER DISCONNECTED';
    if (!st.printer.statusSupported) {
      return strictStatusRequired
          ? 'PRINTER STATUS UNSUPPORTED'
          : 'PRINTER STATUS UNSUPPORTED (COMPATIBLE MODE: WARNING)';
    }
    if (!st.printer.paperOk) return 'PRINTER PAPER OUT';
    if (!st.printer.coverClosed) return 'PRINTER COVER OPEN';
    if (st.printer.offline) return 'PRINTER OFFLINE';
    return 'PRINTER NEEDS ATTENTION';
  }
}
