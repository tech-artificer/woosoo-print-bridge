# Phase 2 Runbook: Printer Library Audit + Reverb TLS

Date: 2026-04-07
Scope: woosoo-print-bridge task 2.8 and task 2.9 from STABILITY_PLAN_2026-04-07.md

## 1) Android Version Audit (Task 2.8 Step 1)

Goal: determine if migration away from `blue_thermal_printer` is urgent.

Procedure:
1. Launch the print-bridge app on each tablet.
2. Open Status screen.
3. Record `Platform` and `OS Version` from the System card.
4. Build an inventory table with columns:
   - Tablet name
   - Android version
   - Printer model
   - Bluetooth mode (Classic/BLE)

Decision rule:
- If any production tablet runs Android 13+, prioritize printer library migration in the next sprint.
- If all tablets are Android 11/12 and soak tests are stable, migration can be deferred to Phase 3.

## 2) Release TLS Validation (Task 2.9)

Goal: ensure release APK connects to Reverb without certificate bypass.

Preconditions:
- Reverb host uses a trusted certificate for the exact hostname in `wsUrl`.
- Device trust store includes the issuing CA if private PKI is used.

Procedure:
1. Build and install release APK.
2. Configure wsUrl to production Reverb host.
3. Start app and verify WebSocket status becomes Connected.
4. Capture logs during startup and connection attempt.

Expected behavior:
- Debug builds may accept self-signed certs.
- Release/profile builds must enforce certificate validation.
- On TLS failure, app logs/report should include actionable message:
  `TLS certificate validation failed for Reverb host...`

Acceptance checks:
- No SSL/certificate errors in release logs.
- Print events received over WebSocket in release build.
- Status screen shows WebSocket Connected in steady state.

## 3) Migration Trigger Checklist (Task 2.8 Step 2)

Begin migration only when all are true:
- Android 13+ present in fleet OR reproducible connection instability on current plugin.
- Chosen replacement supports deployed printer protocol (Classic Bluetooth or BLE).
- Five receipt variants pass hardware print tests.
- 30-minute soak test shows no repeated reconnect/print failures.
