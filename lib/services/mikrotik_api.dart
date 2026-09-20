import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/router_config.dart';
import '../models/hotspot_user.dart';
import '../models/hotspot_profile.dart';
import '../models/active_session.dart';

/// Error con mensaje legible para mostrar directamente en pantalla.
class MikroTikException implements Exception {
  final String message;
  final int? statusCode;

  MikroTikException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class MikroTikApi {
  final RouterConfig config;
  late final String _authHeader;
  late final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  MikroTikApi(this.config) {
    _authHeader =
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';

    // RouterOS usa certificado autofirmado en HTTPS: hay que aceptarlo
    // o la conexion falla siempre con el switch de HTTPS activado.
    final HttpClient io = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true
      ..connectionTimeout = const Duration(seconds: 12);

    _client = IOClient(io);
  }

  Map<String, String> get _headers => <String, String>{
        'Authorization': _authHeader,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  void dispose() => _client.close();

  String _encodeId(String id) => Uri.encodeComponent(id);

  String _bodyText(http.Response r) {
    try {
      return utf8.decode(r.bodyBytes);
    } catch (_) {
      return r.body;
    }
  }

  String _errorFor(http.Response resp) {
    String detail = '';
    try {
      final dynamic decoded = jsonDecode(_bodyText(resp));
      if (decoded is Map) {
        detail = (decoded['detail'] ?? decoded['message'] ?? '').toString();
      }
    } catch (_) {
      // cuerpo no-JSON: se ignora
    }

    switch (resp.statusCode) {
      case 400:
        return detail.isEmpty
            ? 'El router rechazo la peticion (400).'
            : 'El router rechazo la peticion: $detail';
      case 401:
        return 'Usuario o contrasena incorrectos (401).';
      case 403:
        return 'El usuario "${config.username}" no tiene permisos suficientes.\n'
            'En el router: /user group debe incluir las policies "api", "rest-api", "read" y "write".';
      case 404:
        return 'Ruta no encontrada (404).\n'
            'El REST API solo existe en RouterOS v7. Revisa tambien que /ip service "www" este habilitado.';
      default:
        return detail.isEmpty
            ? 'Error ${resp.statusCode} del router.'
            : 'Error ${resp.statusCode}: $detail';
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final Uri uri = Uri.parse('${config.baseUrl}$path');
    final String payload = jsonEncode(body ?? <String, dynamic>{});
    http.Response resp;

    try {
      switch (method) {
        case 'GET':
          resp = await _client.get(uri, headers: _headers).timeout(_timeout);
          break;
        case 'PUT':
          resp = await _client
              .put(uri, headers: _headers, body: payload)
              .timeout(_timeout);
          break;
        case 'PATCH':
          resp = await _client
              .patch(uri, headers: _headers, body: payload)
              .timeout(_timeout);
          break;
        case 'POST':
          resp = await _client
              .post(uri, headers: _headers, body: payload)
              .timeout(_timeout);
          break;
        case 'DELETE':
          resp = await _client.delete(uri, headers: _headers).timeout(_timeout);
          break;
        default:
          throw MikroTikException('Metodo HTTP no soportado: $method');
      }
    } on TimeoutException {
      throw MikroTikException(
          'El router ${config.host} no respondio a tiempo.\n'
          'Revisa que estes conectado a la misma red y que la IP sea correcta.');
    } on SocketException catch (e) {
      final String os = e.osError?.message ?? e.message;
      throw MikroTikException(
          'No se pudo conectar con ${config.host}:${config.port}.\n'
          'Verifica la IP, que estes en la misma red y que el servicio "www" este activo\n'
          'en el router (/ip service enable www).\n($os)');
    } on HandshakeException {
      throw MikroTikException(
          'Fallo el handshake HTTPS con ${config.host}.\n'
          'Prueba desactivando HTTPS y usando el puerto 80.');
    } on http.ClientException catch (e) {
      throw MikroTikException('Error de red: ${e.message}');
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final String text = _bodyText(resp);
      if (text.trim().isEmpty) return null;
      try {
        return jsonDecode(text);
      } catch (_) {
        return null;
      }
    }

    throw MikroTikException(_errorFor(resp), statusCode: resp.statusCode);
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final dynamic data = await _send('GET', path);
    if (data is List) {
      final List<dynamic> raw = data;
      return raw
          .whereType<Map>()
          .map((Map m) => m.cast<String, dynamic>())
          .toList();
    }
    if (data is Map) {
      final Map raw = data;
      return <Map<String, dynamic>>[raw.cast<String, dynamic>()];
    }
    return <Map<String, dynamic>>[];
  }

  // ─── Conexion ─────────────────────────────────────────────
  /// Lanza MikroTikException con el motivo exacto si falla.
  Future<void> testConnection() async {
    await _send('GET', '/system/identity');
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    final List<Map<String, dynamic>> identity =
        await _getList('/system/identity');
    final List<Map<String, dynamic>> resource =
        await _getList('/system/resource');

    List<Map<String, dynamic>> board;
    try {
      board = await _getList('/system/routerboard');
    } catch (_) {
      board = <Map<String, dynamic>>[];
    }

    String pick(List<Map<String, dynamic>> list, String key) =>
        list.isNotEmpty ? (list.first[key]?.toString() ?? '') : '';

    return <String, dynamic>{
      'identity': pick(identity, 'name'),
      'version': pick(resource, 'version'),
      'board': pick(board, 'model'),
      'uptime': pick(resource, 'uptime'),
      'cpu-load': pick(resource, 'cpu-load'),
      'free-memory': pick(resource, 'free-memory'),
      'total-memory': pick(resource, 'total-memory'),
    };
  }

  // ─── Usuarios Hotspot ─────────────────────────────────────
  Future<List<HotspotUser>> getUsers() async {
    final List<Map<String, dynamic>> data = await _getList('/ip/hotspot/user');
    return data.map((Map<String, dynamic> j) => HotspotUser.fromJson(j)).toList();
  }

  Future<Set<String>> getUserNames() async {
    final List<Map<String, dynamic>> data = await _getList('/ip/hotspot/user');
    return data
        .map((Map<String, dynamic> j) => (j['name'] ?? '').toString())
        .where((String n) => n.isNotEmpty)
        .toSet();
  }

  Future<void> addUser(HotspotUser user) async {
    await _send('PUT', '/ip/hotspot/user', body: user.toJson());
  }

  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await _send('PATCH', '/ip/hotspot/user/${_encodeId(id)}', body: data);
  }

  Future<void> deleteUser(String id) async {
    await _send('DELETE', '/ip/hotspot/user/${_encodeId(id)}');
  }

  Future<void> resetUserUptime(String id) async {
    await _send('PATCH', '/ip/hotspot/user/${_encodeId(id)}',
        body: <String, dynamic>{'uptime': '0s'});
  }

  Future<void> toggleUser(String id, bool disable) async {
    await _send('PATCH', '/ip/hotspot/user/${_encodeId(id)}',
        body: <String, dynamic>{'disabled': disable ? 'true' : 'false'});
  }

  // ─── Perfiles Hotspot ─────────────────────────────────────
  Future<List<HotspotProfile>> getProfiles() async {
    final List<Map<String, dynamic>> data =
        await _getList('/ip/hotspot/user/profile');
    return data
        .map((Map<String, dynamic> j) => HotspotProfile.fromJson(j))
        .toList();
  }

  Future<void> addProfile(HotspotProfile profile) async {
    await _send('PUT', '/ip/hotspot/user/profile', body: profile.toJson());
  }

  Future<void> updateProfile(String id, Map<String, dynamic> data) async {
    await _send('PATCH', '/ip/hotspot/user/profile/${_encodeId(id)}',
        body: data);
  }

  Future<void> deleteProfile(String id) async {
    await _send('DELETE', '/ip/hotspot/user/profile/${_encodeId(id)}');
  }

  // ─── Sesiones Activas ─────────────────────────────────────
  Future<List<ActiveSession>> getActiveSessions() async {
    final List<Map<String, dynamic>> data =
        await _getList('/ip/hotspot/active');
    return data
        .map((Map<String, dynamic> j) => ActiveSession.fromJson(j))
        .toList();
  }

  Future<void> disconnectSession(String id) async {
    await _send('DELETE', '/ip/hotspot/active/${_encodeId(id)}');
  }

  // ─── Servidores Hotspot ───────────────────────────────────
  Future<List<String>> getHotspotServers() async {
    final List<Map<String, dynamic>> data = await _getList('/ip/hotspot');
    return data
        .map((Map<String, dynamic> j) => (j['name'] ?? '').toString())
        .where((String n) => n.isNotEmpty)
        .toList();
  }

  // ─── Stats ────────────────────────────────────────────────
  Future<Map<String, int>> getStats() async {
    final List<HotspotUser> users = await getUsers();
    final List<Map<String, dynamic>> active =
        await _getList('/ip/hotspot/active');
    final int expired =
        users.where((HotspotUser u) => u.isExpired || u.disabled).length;
    return <String, int>{
      'totalUsers': users.length,
      'activeNow': active.length,
      'expired': expired,
      'available': users.length - expired,
    };
  }
}
