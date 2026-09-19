class HotspotUser {
  final String? id;
  final String name;
  final String password;
  final String server;
  final String profile;
  final String? limitUptime;
  final String? uptime;
  final String? comment;
  final bool disabled;

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
  });

  bool get isExpired {
    if (limitUptime == null || uptime == null) return false;
    final limit = _parseDuration(limitUptime!);
    final used = _parseDuration(uptime!);
    return limit > Duration.zero && used >= limit;
  }

  double get usagePercent {
    if (limitUptime == null || uptime == null) return 0;
    final limit = _parseDuration(limitUptime!);
    final used = _parseDuration(uptime!);
    if (limit == Duration.zero) return 0;
    final pct = used.inSeconds / limit.inSeconds;
    return pct > 1.0 ? 1.0 : pct;
  }

  String get remainingTime {
    if (limitUptime == null || uptime == null) return 'Ilimitado';
    final limit = _parseDuration(limitUptime!);
    final used = _parseDuration(uptime!);
    if (limit == Duration.zero) return 'Ilimitado';
    final remaining = limit - used;
    if (remaining.isNegative) return 'Expirado';
    return _formatDuration(remaining);
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
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
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

  static Duration _parseDuration(String s) {
    if (s.isEmpty || s == '0s') return Duration.zero;
    int days = 0, hours = 0, minutes = 0, seconds = 0;
    final dMatch = RegExp(r'(\d+)d').firstMatch(s);
    final hMatch = RegExp(r'(\d+)h').firstMatch(s);
    final mMatch = RegExp(r'(\d+)m').firstMatch(s);
    final sMatch = RegExp(r'(\d+)s').firstMatch(s);
    if (dMatch != null) days = int.parse(dMatch.group(1)!);
    if (hMatch != null) hours = int.parse(hMatch.group(1)!);
    if (mMatch != null) minutes = int.parse(mMatch.group(1)!);
    if (sMatch != null) seconds = int.parse(sMatch.group(1)!);
    return Duration(days: days, hours: hours, minutes: minutes, seconds: seconds);
  }

  static String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}m');
    if (parts.isEmpty) parts.add('< 1m');
    return parts.join(' ');
  }
}
