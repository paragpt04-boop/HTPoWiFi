import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/router_config.dart';
import '../services/mikrotik_api.dart';

class RouterProvider extends ChangeNotifier {
  RouterConfig? _config;
  MikroTikApi? _api;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _error;

  RouterConfig? get config => _config;
  MikroTikApi? get api => _api;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('router_config');
    if (saved != null) {
      _config = RouterConfig.fromJson(jsonDecode(saved));
      notifyListeners();
    }
  }

  Future<bool> connect(RouterConfig newConfig) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _api?.dispose();
    _api = MikroTikApi(newConfig);

    final ok = await _api!.testConnection();
    if (ok) {
      _config = newConfig;
      _isConnected = true;
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('router_config', jsonEncode(newConfig.toJson()));
    } else {
      _error = 'No se pudo conectar. Verifica IP, usuario y contraseña.';
      _isConnected = false;
      _api?.dispose();
      _api = null;
    }

    _isLoading = false;
    notifyListeners();
    return ok;
  }

  void disconnect() {
    _api?.dispose();
    _api = null;
    _isConnected = false;
    _error = null;
    notifyListeners();
  }

  Future<void> clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('router_config');
    _config = null;
    disconnect();
  }
}
