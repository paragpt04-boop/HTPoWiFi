import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/router_config.dart';
import '../models/hotspot_user.dart';
import '../models/hotspot_profile.dart';
import '../models/active_session.dart';
import '../utils/ros_time.dart';

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
    final HttpClient io = HttpClient();
    io.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    io.connectionTimeout = const Duration(seconds: 12);

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

  /// Reinicia el tiempo consumido (y el tráfico) del usuario con el comando
  /// nativo `reset-counters`. Si [user] tiene etiqueta [EXP:...], la quita.
  Future<void> resetUserUptime(String id, {HotspotUser? user}) async {
    try {
      await _send('POST', '/ip/hotspot/user/reset-counters',
          body: <String, dynamic>{'numbers': id});
    } on MikroTikException catch (e) {
      if (e.statusCode != 400) rethrow;
      await _send('POST', '/ip/hotspot/user/reset-counters',
          body: <String, dynamic>{'.id': id});
    }
    if (user != null && user.hasExpTag) {
      await updateUser(id, <String, dynamic>{'comment': user.cleanComment});
    }
  }

  /// Renueva un usuario expirado: nuevo límite, contador a cero,
  /// sin etiqueta de expiración y habilitado.
  Future<void> renewUser(HotspotUser user, String newLimit) async {
    if (user.id == null) return;
    await updateUser(user.id!, <String, dynamic>{
      'limit-uptime': newLimit,
      'comment': user.cleanComment,
      'disabled': 'false',
    });
    await resetUserUptime(user.id!);
  }

  // ─── Registro de expiración ───────────────────────────────
  static const String expiryScheduler = 'htpowifi-expiry';

  /// Script que corre cada minuto en el router. Cuando un usuario llega a su
  /// limit-uptime escribe "[EXP:fecha hora]" en el comentario; si después se
  /// le reinicia el tiempo (desde la app o Winbox) quita la etiqueta.
  static const String _expiryScript = r'''
:local now ([/system clock get date] . " " . [/system clock get time])
:foreach u in=[/ip hotspot user find] do={
  :local lim [/ip hotspot user get $u limit-uptime]
  :if ([:typeof $lim] = "time") do={
    :if ($lim > 0s) do={
      :local up [/ip hotspot user get $u uptime]
      :local c [/ip hotspot user get $u comment]
      :if ([:typeof $c] != "str") do={ :set c "" }
      :local p [:find $c "[EXP:"]
      :if ($up >= $lim) do={
        :if ([:typeof $p] = "nil") do={
          :if ([:len $c] > 0) do={ :set c ($c . " ") }
          /ip hotspot user set $u comment=($c . "[EXP:" . $now . "]")
        }
      } else={
        :if ([:typeof $p] != "nil") do={
          :local e [:find $c "]" $p]
          :local a [:pick $c 0 $p]
          :local b ""
          :if ([:typeof $e] != "nil") do={ :set b [:pick $c ($e + 1) [:len $c]] }
          :if ([:len $a] > 0) do={
            :if ([:pick $a ([:len $a] - 1)] = " ") do={ :set a [:pick $a 0 ([:len $a] - 1)] }
          }
          /ip hotspot user set $u comment=($a . $b)
        }
      }
    }
  }
}
''';

  /// true si el scheduler del registro de expiración existe y está activo.
  Future<bool> isExpiryTrackerInstalled() async {
    final List<Map<String, dynamic>> list = await _getList('/system/scheduler');
    return list.any((Map<String, dynamic> s) =>
        s['name'] == expiryScheduler && s['disabled'] != 'true');
  }

  /// Crea (o actualiza) el scheduler del registro de expiración.
  /// No toca perfiles ni scripts existentes.
  Future<void> installExpiryTracker() async {
    final List<Map<String, dynamic>> list = await _getList('/system/scheduler');
    final Map<String, dynamic> body = <String, dynamic>{
      'interval': '1m',
      'on-event': _expiryScript,
      'policy': 'read,write,test',
      'disabled': 'false',
      'comment': 'HTPoWiFi - registra la hora de expiracion de usuarios hotspot',
    };
    Map<String, dynamic>? existing;
    for (final Map<String, dynamic> s in list) {
      if (s['name'] == expiryScheduler) existing = s;
    }
    if (existing != null && existing['.id'] != null) {
      await _send('PATCH',
          '/system/scheduler/${_encodeId(existing['.id'].toString())}',
          body: body);
    } else {
      await _send('PUT', '/system/scheduler',
          body: <String, dynamic>{'name': expiryScheduler, ...body});
    }
  }

  /// Marca en el router los usuarios que ya estaban expirados antes de activar
  /// el registro: usa la hora del log si existe, si no "[EXP:?]".
  /// Devuelve cuántos usuarios se marcaron.
  Future<int> backfillExpiryTags(
      List<HotspotUser> users, Map<String, DateTime> logTimes) async {
    int count = 0;
    for (final HotspotUser u in users) {
      if (u.id == null || !u.isExpired || u.hasExpTag) continue;
      final DateTime? t = logTimes[u.name];
      final String value = t == null ? '?' : _rosStamp(t);
      await updateUser(u.id!, <String, dynamic>{'comment': u.commentWithTag(value)});
      count++;
    }
    return count;
  }

  /// "2026-10-01 14:32:05" — formato ISO que entiende la app.
  static String _rosStamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// Fecha y hora actual del router (para calcular "hace cuánto").
  Future<DateTime?> getRouterClock() async {
    final List<Map<String, dynamic>> c = await _getList('/system/clock');
    if (c.isEmpty) return null;
    return RosTime.parseDateTime(
        (c.first['date'] ?? '').toString(), (c.first['time'] ?? '').toString());
  }

  /// Último "logged out" de cada usuario según /log del router.
  /// El log vive en RAM: se pierde al reiniciar y guarda ~1000 líneas.
  Future<Map<String, DateTime>> getLastLogoutTimes(DateTime routerNow) async {
    final Map<String, DateTime> result = <String, DateTime>{};
    List<Map<String, dynamic>> logs;
    try {
      logs = await _getList('/log');
    } catch (_) {
      return result;
    }
    final RegExp re = RegExp(r'(\S+) \([0-9a-fA-F\.:]+\): logged out');
    for (final Map<String, dynamic> l in logs) {
      final String msg = (l['message'] ?? '').toString();
      final Match? m = re.firstMatch(msg);
      if (m == null) continue;
      final DateTime? t =
          RosTime.parseLogTime((l['time'] ?? '').toString(), routerNow);
      if (t == null) continue;
      final String user = m.group(1)!;
      final DateTime? prev = result[user];
      if (prev == null || t.isAfter(prev)) result[user] = t;
    }
    return result;
  }

  /// Elimina varios usuarios. Devuelve el primer error o null.
  Future<String?> deleteUsers(List<HotspotUser> users) async {
    String? err;
    for (final HotspotUser u in users) {
      if (u.id == null) continue;
      try {
        await deleteUser(u.id!);
      } on MikroTikException catch (e) {
        err ??= e.message;
      }
    }
    return err;
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

  /// true si hay al menos un servidor hotspot configurado
  Future<bool> isHotspotConfigured() async {
    try {
      final List<String> servers = await getHotspotServers();
      return servers.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Todas las interfaces del router
  Future<List<Map<String, dynamic>>> getInterfaces() async {
    return await _getList('/interface');
  }

  /// Mapa username → password para mostrar en sesiones activas
  Future<Map<String, String>> getUserPasswordMap() async {
    final List<Map<String, dynamic>> list = await _getList('/ip/hotspot/user');
    final Map<String, String> map = <String, String>{};
    for (final Map<String, dynamic> u in list) {
      final String name = (u['name'] ?? '').toString();
      final String pass = (u['password'] ?? '').toString();
      if (name.isNotEmpty) map[name] = pass;
    }
    return map;
  }

  /// Configura el hotspot completo desde cero
  Future<void> setupHotspot({
    required String interface,
    required String gatewayIp,
    required String networkCidr,
    required String poolRange,
    required String serverName,
    void Function(String)? onProgress,
  }) async {
    final String prefix = networkCidr.split('/').last;

    void log(String msg) => onProgress?.call(msg);

    // 1. IP en la interfaz
    log('Asignando IP $gatewayIp a $interface...');
    try {
      await _send('PUT', '/ip/address', body: <String, dynamic>{
        'address': '$gatewayIp/$prefix',
        'interface': interface,
      });
    } on MikroTikException catch (e) {
      // 400 = ya existe la IP, ignorar
      if (e.statusCode != 400) rethrow;
      log('  IP ya asignada, continuando.');
    }

    // 2. Pool
    log('Creando pool $poolRange...');
    try {
      await _send('PUT', '/ip/pool', body: <String, dynamic>{
        'name': 'hs-pool',
        'ranges': poolRange,
      });
    } on MikroTikException catch (e) {
      if (e.statusCode != 400) rethrow;
      log('  Pool ya existe, continuando.');
    }

    // 3. DHCP server
    log('Configurando DHCP en $interface...');
    try {
      await _send('PUT', '/ip/dhcp-server', body: <String, dynamic>{
        'name': 'dhcp-hotspot',
        'interface': interface,
        'address-pool': 'hs-pool',
        'lease-time': '10m',
        'disabled': 'false',
      });
    } on MikroTikException catch (e) {
      if (e.statusCode != 400) rethrow;
      log('  DHCP ya existe, continuando.');
    }

    // 4. DHCP network
    try {
      await _send('PUT', '/ip/dhcp-server/network', body: <String, dynamic>{
        'address': networkCidr,
        'gateway': gatewayIp,
        'dns-server': gatewayIp,
      });
    } on MikroTikException catch (e) {
      if (e.statusCode != 400) rethrow;
    }

    // 5. Server profile
    log('Creando perfil de servidor hotspot...');
    try {
      await _send('PUT', '/ip/hotspot/profile', body: <String, dynamic>{
        'name': 'hsprof1',
        'hotspot-address': gatewayIp,
        'dns-name': '',
        'use-radius': 'false',
      });
    } on MikroTikException catch (e) {
      if (e.statusCode != 400) rethrow;
      log('  Perfil ya existe, continuando.');
    }

    // 6. User profile (default puede existir)
    log('Configurando perfil de usuario default...');
    try {
      await _send('PUT', '/ip/hotspot/user/profile', body: <String, dynamic>{
        'name': 'default',
        'session-timeout': '1h',
        'shared-users': '1',
      });
    } catch (_) {}

    // 7. Hotspot server
    log('Creando servidor hotspot $serverName...');
    await _send('PUT', '/ip/hotspot', body: <String, dynamic>{
      'name': serverName,
      'interface': interface,
      'address-pool': 'hs-pool',
      'profile': 'hsprof1',
      'disabled': 'false',
    });
  }

  // ─── Stats ────────────────────────────────────────────────
  Future<Map<String, int>> getStats() async {
    final List<HotspotUser> users = await getUsers();
    final List<Map<String, dynamic>> active =
        await _getList('/ip/hotspot/active');
    return <String, int>{
      'totalUsers': users.length,
      'activeNow': active.length,
      'expired': users.where((HotspotUser u) => u.isExpired).length,
      'disabled': users.where((HotspotUser u) => u.disabled).length,
      'available': users.where((HotspotUser u) => u.isAvailable).length,
    };
  }
}
