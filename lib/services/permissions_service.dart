import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  Future<bool> ensureBluetoothPermissions() async {
    final connect = await Permission.bluetoothConnect.request();
    final scan = await Permission.bluetoothScan.request();
    return connect.isGranted && scan.isGranted;
  }
}
