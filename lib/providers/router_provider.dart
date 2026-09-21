import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/router_config.dart';
import '../models/hotspot_profile.dart';
import '../services/mikrotik_api.dart';

class RouterProvider extends ChangeNotifier {
  RouterConfig? _config;
  MikroTikApi? _api;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _error;

  List<String> _servers = <String>['all'];
  List<String> _profiles = <String>['default'];
  String _selectedServer = 'all';
  String _selectedProfile = 'default';
  bool _hotspotConfigured = false;

  RouterConfig? get config => _config;
  MikroTikApi? get api => _api;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hotspotConfigured => _hotspotConfigured;

  List<String> get servers => _servers;
  List<String> get profiles => _profiles;
  String get selectedServer => _selectedServer;
  String get selectedProfile => _selectedProfile;

  void setServer(String value) {
    _selectedServer = value;
    notifyListeners();
  }

  void setProfile(String value) {
    _selectedProfile = value;
    notifyListeners();
  }

  Future<void> loadSavedConfig() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('router_config');
    if (saved != null) {
      try {
        _config = RouterConfig.fromJson(
            jsonDecode(saved) as Map<String, dynamic>);
        notifyListeners();
      } catch (_) {
        // config guardada corrupta: se ignora
      }
    }
  }

  Future<bool> connect(RouterConfig newConfig) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _api?.dispose();
    final MikroTikApi candidate = MikroTikApi(newConfig);
    bool ok = false;

    try {
      await candidate.testConnection();
      ok = true;
    } on MikroTikException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error inesperado al conectar: $e';
    }

    if (ok) {
      _api = candidate;
      _config = newConfig;
      _isConnected = true;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('router_config', jsonEncode(newConfig.toJson()));

      await _loadMeta();
    } else {
      candidate.dispose();
      _api = null;
      _isConnected = false;
    }

    _isLoading = false;
    notifyListeners();
    return ok;
  }

  /// Carga servidores hotspot y perfiles. Nunca tumba la conexion:
  /// si el usuario del router no tiene permiso de lectura ahi, usa valores por defecto.
  Future<void> _loadMeta() async {
    final MikroTikApi? api = _api;
    if (api == null) return;

    List<String> servers = <String>[];
    try {
      servers = await api.getHotspotServers();
    } catch (_) {
      servers = <String>[];
    }
    _hotspotConfigured = servers.isNotEmpty;
    // "all" permite que el usuario entre por cualquier servidor hotspot.
    if (!servers.contains('all')) servers.insert(0, 'all');
    _servers = servers;
    if (!_servers.contains(_selectedServer)) _selectedServer = 'all';

    List<String> profiles = <String>[];
    try {
      final List<HotspotProfile> list = await api.getProfiles();
      profiles = list
          .map((HotspotProfile p) => p.name)
          .where((String n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      profiles = <String>[];
    }
    if (profiles.isEmpty) profiles = <String>['default'];
    _profiles = profiles;
    if (!_profiles.contains(_selectedProfile)) {
      _selectedProfile =
          _profiles.contains('default') ? 'default' : _profiles.first;
    }
  }

  Future<void> refreshMeta() async {
    await _loadMeta();
    notifyListeners();
  }

  void disconnect() {
    _api?.dispose();
    _api = null;
    _isConnected = false;
    _error = null;
    notifyListeners();
  }

  Future<void> clearSaved() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('router_config');
    _config = null;
    disconnect();
  }
}
