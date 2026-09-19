class RouterConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useSsl;

  RouterConfig({
    required this.host,
    this.port = 80,
    required this.username,
    required this.password,
    this.useSsl = false,
  });

  String get baseUrl {
    final scheme = useSsl ? 'https' : 'http';
    final portPart = (useSsl && port == 443) || (!useSsl && port == 80)
        ? ''
        : ':$port';
    return '$scheme://$host$portPart/rest';
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'useSsl': useSsl,
      };

  factory RouterConfig.fromJson(Map<String, dynamic> json) => RouterConfig(
        host: json['host'] ?? '',
        port: json['port'] ?? 80,
        username: json['username'] ?? '',
        password: json['password'] ?? '',
        useSsl: json['useSsl'] ?? false,
      );
}
