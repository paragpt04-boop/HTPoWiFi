import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/router_config.dart';
import '../models/hotspot_user.dart';
import '../models/hotspot_profile.dart';
import '../models/active_session.dart';

class MikroTikApi {
  final RouterConfig config;
  late final String _authHeader;
  late final http.Client _client;

  MikroTikApi(this.config) {
    _authHeader =
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    _client = http.Client();
  }

  Map<String, String> get _headers => {
        'Authorization': _authHeader,
        'Content-Type': 'application/json',
      };

  void dispose() => _client.close();

  // ─── Conexión ─────────────────────────────────────────────
  Future<bool> testConnection() async {
    try {
      final resp = await _client
          .get(Uri.parse('${config.baseUrl}/system/identity'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    final identity = await _get('/system/identity');
    final resource = await _get('/system/resource');
    final routerboard = await _get('/system/routerboard');
    return {
      'identity': identity.isNotEmpty ? identity[0]['name'] ?? '' : '',
      'version': resource.isNotEmpty ? resource[0]['version'] ?? '' : '',
      'board': routerboard.isNotEmpty
          ? routerboard[0]['model'] ?? ''
          : '',
      'uptime': resource.isNotEmpty ? resource[0]['uptime'] ?? '' : '',
      'cpu-load': resource.isNotEmpty ? resource[0]['cpu-load'] ?? '' : '',
      'free-memory': resource.isNotEmpty
          ? resource[0]['free-memory'] ?? ''
          : '',
      'total-memory': resource.isNotEmpty
          ? resource[0]['total-memory'] ?? ''
          : '',
    };
  }

  // ─── Usuarios Hotspot ─────────────────────────────────────
  Future<List<HotspotUser>> getUsers() async {
    final data = await _get('/ip/hotspot/user');
    return data.map((j) => HotspotUser.fromJson(j)).toList();
  }

  Future<bool> addUser(HotspotUser user) async {
    return await _put('/ip/hotspot/user', user.toJson());
  }

  Future<bool> updateUser(String id, Map<String, dynamic> data) async {
    return await _patch('/ip/hotspot/user/$id', data);
  }

  Future<bool> deleteUser(String id) async {
    return await _delete('/ip/hotspot/user/$id');
  }

  Future<bool> resetUserUptime(String id) async {
    return await _patch('/ip/hotspot/user/$id', {'uptime': '0s'});
  }

  Future<bool> toggleUser(String id, bool disable) async {
    return await _patch(
        '/ip/hotspot/user/$id', {'disabled': disable ? 'true' : 'false'});
  }

  // ─── Perfiles Hotspot ─────────────────────────────────────
  Future<List<HotspotProfile>> getProfiles() async {
    final data = await _get('/ip/hotspot/user/profile');
    return data.map((j) => HotspotProfile.fromJson(j)).toList();
  }

  Future<bool> addProfile(HotspotProfile profile) async {
    return await _put('/ip/hotspot/user/profile', profile.toJson());
  }

  Future<bool> updateProfile(String id, Map<String, dynamic> data) async {
    return await _patch('/ip/hotspot/user/profile/$id', data);
  }

  Future<bool> deleteProfile(String id) async {
    return await _delete('/ip/hotspot/user/profile/$id');
  }

  // ─── Sesiones Activas ─────────────────────────────────────
  Future<List<ActiveSession>> getActiveSessions() async {
    final data = await _get('/ip/hotspot/active');
    return data.map((j) => ActiveSession.fromJson(j)).toList();
  }

  Future<bool> disconnectSession(String id) async {
    try {
      final resp = await _client.post(
        Uri.parse('${config.baseUrl}/ip/hotspot/active/remove'),
        headers: _headers,
        body: jsonEncode({'.id': id}),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─── Servidores Hotspot ───────────────────────────────────
  Future<List<String>> getHotspotServers() async {
    final data = await _get('/ip/hotspot');
    return data.map<String>((j) => j['name']?.toString() ?? '').toList();
  }

  // ─── Stats ────────────────────────────────────────────────
  Future<Map<String, int>> getStats() async {
    final users = await _get('/ip/hotspot/user');
    final active = await _get('/ip/hotspot/active');
    final expired = users.where((u) {
      final limit = u['limit-uptime'];
      final uptime = u['uptime'];
      if (limit == null || uptime == null) return false;
      return uptime == limit || u['disabled'] == 'true';
    }).length;
    return {
      'totalUsers': users.length,
      'activeNow': active.length,
      'expired': expired,
      'available': users.length - expired,
    };
  }

  // ─── HTTP helpers ─────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _get(String path) async {
    try {
      final resp = await _client
          .get(Uri.parse('${config.baseUrl}$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
        if (decoded is Map) {
          return [decoded.cast<String, dynamic>()];
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> _put(String path, Map<String, dynamic> body) async {
    try {
      final resp = await _client
          .put(Uri.parse('${config.baseUrl}$path'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _patch(String path, Map<String, dynamic> body) async {
    try {
      final resp = await _client
          .patch(Uri.parse('${config.baseUrl}$path'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _delete(String path) async {
    try {
      final resp = await _client
          .delete(Uri.parse('${config.baseUrl}$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
