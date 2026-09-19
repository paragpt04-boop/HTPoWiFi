class HotspotProfile {
  final String? id;
  final String name;
  final String? rateLimit;
  final int sharedUsers;
  final String? idleTimeout;
  final String? keepaliveTimeout;
  final String? statusAutorefresh;
  final String? macCookieTimeout;
  final bool addMacCookie;

  HotspotProfile({
    this.id,
    required this.name,
    this.rateLimit,
    this.sharedUsers = 1,
    this.idleTimeout,
    this.keepaliveTimeout,
    this.statusAutorefresh,
    this.macCookieTimeout,
    this.addMacCookie = true,
  });

  String get uploadSpeed {
    if (rateLimit == null || rateLimit!.isEmpty) return 'Sin límite';
    final parts = rateLimit!.split('/');
    return parts.isNotEmpty ? parts[0] : rateLimit!;
  }

  String get downloadSpeed {
    if (rateLimit == null || rateLimit!.isEmpty) return 'Sin límite';
    final parts = rateLimit!.split('/');
    return parts.length > 1 ? parts[1] : parts[0];
  }

  factory HotspotProfile.fromJson(Map<String, dynamic> json) => HotspotProfile(
        id: json['.id'],
        name: json['name'] ?? '',
        rateLimit: json['rate-limit'],
        sharedUsers: int.tryParse(json['shared-users']?.toString() ?? '1') ?? 1,
        idleTimeout: json['idle-timeout'],
        keepaliveTimeout: json['keepalive-timeout'],
        statusAutorefresh: json['status-autorefresh'],
        macCookieTimeout: json['mac-cookie-timeout'],
        addMacCookie: json['add-mac-cookie'] != 'false',
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'shared-users': sharedUsers.toString(),
    };
    if (rateLimit != null && rateLimit!.isNotEmpty) {
      map['rate-limit'] = rateLimit;
    }
    return map;
  }
}
