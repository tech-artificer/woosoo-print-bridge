import 'package:intl/intl.dart';

class TimeFmt {
  static final DateFormat _dt = DateFormat('yyyy-MM-dd HH:mm:ss');
  static String dt(DateTime d) => _dt.format(d.toLocal());
}
