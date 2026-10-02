import '../utils/ros_time.dart';

/// Origen de la fecha de expiración mostrada en la app.
enum ExpirySource {
  /// Marca exacta escrita por el script "htpowifi-expiry" del router.
  tracker,

  /// Último "logged out" encontrado en /log (aproximado; se pierde al reiniciar).
  log,

  /// Expiró antes de activar el registro y no aparece en el log.
  unknown,
}

class ExpiryInfo {
  final DateTime? at;
  final ExpirySource source;

  const ExpiryInfo(this.at, this.source);

  static const ExpiryInfo none = ExpiryInfo(null, ExpirySource.unknown);
}

class HotspotUser {
  /// Etiqueta que el router añade al comentario cuando el usuario expira.
  /// Formato: "[EXP:2026-10-01 14:32:05]" o "[EXP:?]" (hora desconocida).
  static const String expTagStart = '[EXP:';
  static final RegExp _expTagRe = RegExp(r'\s*\[EXP:([^\]]*)\]');

  final String? id;
  final String name;
  final String password;
  final String server;
  final String profile;
  final String? limitUptime;
  final String? uptime;
  final String? comment;
  final bool disabled;
  final int bytesIn;
  final int bytesOut;
  final String? macAddress;

  HotspotUser({
    this.id,
    required this.name,
    required this.password,
    this.server = 'all',
    this.profile = 'default',
    this.limitUptime,
    this.uptime,
    this.comment,
    this.disabled = false,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.macAddress,
  });

  // ─── Tiempos ──────────────────────────────────────────────
  Duration get limitDuration =>
      limitUptime == null ? Duration.zero : parseDuration(limitUptime!);

  Duration get usedDuration =>
      uptime == null ? Duration.zero : parseDuration(uptime!);

  bool get hasLimit => limitDuration > Duration.zero;

  bool get isExpired => hasLimit && usedDuration >= limitDuration;

  /// Nunca se ha conectado
  bool get isUnused => usedDuration == Duration.zero;

  /// Ni expirado ni deshabilitado
  bool get isAvailable => !isExpired && !disabled;

  double get usagePercent {
    if (!hasLimit) return 0;
    final double pct = usedDuration.inSeconds / limitDuration.inSeconds;
    return pct > 1.0 ? 1.0 : pct;
  }

  String get remainingTime {
    if (!hasLimit) return 'Ilimitado';
    final Duration remaining = limitDuration - usedDuration;
    if (remaining.isNegative || remaining == Duration.zero) return 'Expirado';
    return _formatDuration(remaining);
  }

  // ─── Tráfico ──────────────────────────────────────────────
  int get totalBytes => bytesIn + bytesOut;

  // ─── Comentario / marca de expiración ─────────────────────
  /// Contenido crudo de la etiqueta [EXP:...] o null si no existe.
  String? get expTagValue {
    final Match? m = _expTagRe.firstMatch(comment ?? '');
    return m?.group(1);
  }

  bool get hasExpTag => expTagValue != null;

  /// Fecha guardada por el router, si es válida.
  DateTime? get trackedExpiry {
    final String? v = expTagValue;
    if (v == null || v.trim() == '?' || v.trim().isEmpty) return null;
    return RosTime.parseStamp(v);
  }

  /// Comentario sin la etiqueta de expiración.
  String get cleanComment => (comment ?? '').replaceAll(_expTagRe, '').trim();

  /// Comentario con la etiqueta indicada (reemplaza cualquier otra).
  String commentWithTag(String value) {
    final String base = cleanComment;
    final String tag = '$expTagStart$value]';
    return base.isEmpty ? tag : '$base $tag';
  }

  factory HotspotUser.fromJson(Map<String, dynamic> json) => HotspotUser(
        id: json['.id'],
        name: json['name'] ?? '',
        password: json['password'] ?? '',
        server: json['server'] ?? 'all',
        profile: json['profile'] ?? 'default',
        limitUptime: json['limit-uptime'],
        uptime: json['uptime'],
        comment: json['comment'],
        disabled: json['disabled'] == 'true',
        bytesIn: int.tryParse('${json['bytes-in'] ?? 0}') ?? 0,
        bytesOut: int.tryParse('${json['bytes-out'] ?? 0}') ?? 0,
        macAddress: json['mac-address'],
      );

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = <String, dynamic>{
      'name': name,
      'password': password,
      'server': server,
      'profile': profile,
    };
    if (limitUptime != null && limitUptime!.isNotEmpty) {
      map['limit-uptime'] = limitUptime;
    }
    if (comment != null && comment!.isNotEmpty) {
      map['comment'] = comment;
    }
    return map;
  }

  /// Convierte "1w2d3h4m5s" (formato RouterOS) a Duration.
  /// También acepta "hh:mm:ss" y "1d12:00:00".
  static Duration parseDuration(String s) {
    s = s.trim();
    if (s.isEmpty || s == '0s') return Duration.zero;

    // Formato con reloj: "12:00:00" o "1d12:00:00"
    final Match? clock =
        RegExp(r'^(?:(\d+)w)?(?:(\d+)d)?(\d+):(\d{2}):(\d{2})$').firstMatch(s);
    if (clock != null) {
      return Duration(
        days: int.parse(clock.group(1) ?? '0') * 7 +
            int.parse(clock.group(2) ?? '0'),
        hours: int.parse(clock.group(3)!),
        minutes: int.parse(clock.group(4)!),
        seconds: int.parse(clock.group(5)!),
      );
    }

    int weeks = 0, days = 0, hours = 0, minutes = 0, seconds = 0;
    final Match? wMatch = RegExp(r'(\d+)w').firstMatch(s);
    final Match? dMatch = RegExp(r'(\d+)d').firstMatch(s);
    final Match? hMatch = RegExp(r'(\d+)h').firstMatch(s);
    // (?!s) evita que "20ms" se lea como minutos
    final Match? mMatch = RegExp(r'(\d+)m(?!s)').firstMatch(s);
    final Match? sMatch = RegExp(r'(\d+)s').firstMatch(s);
    if (wMatch != null) weeks = int.parse(wMatch.group(1)!);
    if (dMatch != null) days = int.parse(dMatch.group(1)!);
    if (hMatch != null) hours = int.parse(hMatch.group(1)!);
    if (mMatch != null) minutes = int.parse(mMatch.group(1)!);
    if (sMatch != null) seconds = int.parse(sMatch.group(1)!);
    return Duration(
      days: weeks * 7 + days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

  static String _formatDuration(Duration d) {
    final int days = d.inDays;
    final int hours = d.inHours % 24;
    final int minutes = d.inMinutes % 60;
    final List<String> parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}m');
    if (parts.isEmpty) parts.add('< 1m');
    return parts.join(' ');
  }
}
