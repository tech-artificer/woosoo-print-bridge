import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class LoggerService {
  late final Logger _logger;
  File? _file;
  IOSink? _sink;

  LoggerService() {
    _logger = Logger(printer: PrettyPrinter(methodCount: 0, dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart));
  }

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final logsDir = Directory('${dir.path}/logs');
    if (!await logsDir.exists()) await logsDir.create(recursive: true);
    _file = File('${logsDir.path}/app_log.txt');
    _sink = _file!.openWrite(mode: FileMode.append);
    i('Logger initialized at ${_file!.path}');
  }

  String? get logPath => _file?.path;

  void _write(String level, String msg) {
    try {
      _sink?.writeln('[$level] $msg');
      _sink?.flush();
    } catch (e) {
      // Sink may be closed, ignore
    }
  }

  void i(String msg) { _logger.i(msg); _write('INFO', msg); }
  void d(String msg) { _logger.d(msg); _write('DEBUG', msg); }
  void w(String msg) { _logger.w(msg); _write('WARN', msg); }
  void e(String msg, [Object? err, StackTrace? st]) { _logger.e(msg, error: err, stackTrace: st); _write('ERROR', '$msg ${err ?? ''}'); }

  Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (e) {
      // Sink may already be closed, ignore
    }
  }
}
