import 'package:intl/intl.dart';

/// Utilidades para leer fechas/horas en los formatos de RouterOS v7
/// y para mostrar duraciones y tráfico de forma legible.
class RosTime {
  static const Map<String, int> _months = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Fecha de `/system clock` → DateTime.
  /// Soporta "2026-10-01" (v7.10+) y "oct/01/2026" (v7 anteriores).
  static DateTime? parseDateTime(String date, String time) {
    final DateTime? d = _parseDate(date.trim());
    final List<int>? t = _parseTime(time.trim());
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t[0], t[1], t[2]);
  }

  /// Texto "fecha hora" guardado por el script del router, ej:
  /// "2026-10-01 14:32:05" o "oct/01/2026 14:32:05".
  static DateTime? parseStamp(String stamp) {
    final List<String> parts = stamp.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    return parseDateTime(parts[0], parts[1]);
  }

  /// Hora de una línea de `/log`. Formatos posibles:
  /// "14:32:05" (hoy), "oct/01 14:32:05", "10-01 14:32:05",
  /// "2026-10-01 14:32:05", "oct/01/2026 14:32:05".
  static DateTime? parseLogTime(String raw, DateTime routerNow) {
    final String s = raw.trim();
    final List<String> parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final List<int>? t = _parseTime(parts[0]);
      if (t == null) return null;
      return DateTime(
          routerNow.year, routerNow.month, routerNow.day, t[0], t[1], t[2]);
    }
    final List<int>? t = _parseTime(parts[1]);
    if (t == null) return null;
    final String d = parts[0];

    DateTime? date = _parseDate(d);
    if (date == null) {
      // Sin año: "oct/01" o "10-01"
      int? month;
      int? day;
      final Match? a = RegExp(r'^([a-zA-Z]{3})/(\d{1,2})$').firstMatch(d);
      final Match? b = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(d);
      if (a != null) {
        month = _months[a.group(1)!.toLowerCase()];
        day = int.tryParse(a.group(2)!);
      } else if (b != null) {
        month = int.tryParse(b.group(1)!);
        day = int.tryParse(b.group(2)!);
      }
      if (month == null || day == null) return null;
      int year = routerNow.year;
      // Si la fecha queda en el futuro, es del año anterior
      if (DateTime(year, month, day).isAfter(routerNow)) year--;
      date = DateTime(year, month, day);
    }
    return DateTime(date.year, date.month, date.day, t[0], t[1], t[2]);
  }

  static DateTime? _parseDate(String d) {
    final Match? iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(d);
    if (iso != null) {
      return DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
    }
    final Match? old =
        RegExp(r'^([a-zA-Z]{3})/(\d{1,2})/(\d{4})$').firstMatch(d);
    if (old != null) {
      final int? m = _months[old.group(1)!.toLowerCase()];
      if (m == null) return null;
      return DateTime(
          int.parse(old.group(3)!), m, int.parse(old.group(2)!));
    }
    return null;
  }

  static List<int>? _parseTime(String t) {
    final Match? m = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})').firstMatch(t);
    if (m == null) return null;
    return <int>[
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    ];
  }

  /// "dd/MM/yyyy HH:mm"
  static String formatDateTime(DateTime d) =>
      DateFormat('dd/MM/yyyy HH:mm').format(d);

  /// Duración humana: "3d 4h", "2h 15m", "12m", "< 1m"
  static String formatAgo(Duration d) {
    if (d.isNegative) return '< 1m';
    final int days = d.inDays;
    final int hours = d.inHours % 24;
    final int minutes = d.inMinutes % 60;
    if (days >= 30) {
      final int months = days ~/ 30;
      final int rest = days % 30;
      return rest > 0 ? '${months}mes ${rest}d' : '${months}mes';
    }
    if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    if (hours > 0) return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    if (minutes > 0) return '${minutes}m';
    return '< 1m';
  }

  /// Duración RouterOS legible: "1d 2h 3m"
  static String formatDuration(Duration d) {
    final int days = d.inDays;
    final int hours = d.inHours % 24;
    final int minutes = d.inMinutes % 60;
    final int seconds = d.inSeconds % 60;
    final List<String> p = <String>[];
    if (days > 0) p.add('${days}d');
    if (hours > 0) p.add('${hours}h');
    if (minutes > 0) p.add('${minutes}m');
    if (p.isEmpty) p.add('${seconds}s');
    return p.join(' ');
  }

  /// Bytes → "345 KB", "12.5 MB", "1.20 GB"
  static String formatBytes(int b) {
    if (b <= 0) return '0 B';
    const double k = 1024;
    if (b < k) return '$b B';
    if (b < k * k) return '${(b / k).toStringAsFixed(0)} KB';
    if (b < k * k * k) return '${(b / (k * k)).toStringAsFixed(1)} MB';
    return '${(b / (k * k * k)).toStringAsFixed(2)} GB';
  }
}
