class ActiveSession {
  final String? id;
  final String user;
  final String address;
  final String macAddress;
  final String uptime;
  final String server;
  final String? bytesIn;
  final String? bytesOut;

  ActiveSession({
    this.id,
    required this.user,
    required this.address,
    required this.macAddress,
    required this.uptime,
    required this.server,
    this.bytesIn,
    this.bytesOut,
  });

  String get trafficIn => _formatBytes(bytesIn);
  String get trafficOut => _formatBytes(bytesOut);

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
        id: json['.id'],
        user: json['user'] ?? '',
        address: json['address'] ?? '',
        macAddress: json['mac-address'] ?? '',
        uptime: json['uptime'] ?? '0s',
        server: json['server'] ?? '',
        bytesIn: json['bytes-in'],
        bytesOut: json['bytes-out'],
      );

  static String _formatBytes(String? bytes) {
    if (bytes == null || bytes.isEmpty) return '0 B';
    final b = int.tryParse(bytes) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}
