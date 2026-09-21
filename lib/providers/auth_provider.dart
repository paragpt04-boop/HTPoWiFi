import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole { none, admin, vendor }

class AuthProvider extends ChangeNotifier {
  AppRole _role = AppRole.none;
  String _vendorPin = '';
  String _adminPin = '';

  AppRole get role => _role;
  bool get isAdmin => _role == AppRole.admin;
  bool get isVendor => _role == AppRole.vendor;
  bool get hasRole => _role != AppRole.none;
  bool get hasVendorPin => _vendorPin.isNotEmpty;
  bool get hasAdminPin => _adminPin.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _vendorPin = prefs.getString('vendor_pin') ?? '';
    _adminPin = prefs.getString('admin_pin') ?? '';
  }

  Future<void> saveVendorPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendor_pin', pin);
    _vendorPin = pin;
    notifyListeners();
  }

  Future<void> saveAdminPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_pin', pin);
    _adminPin = pin;
    notifyListeners();
  }

  Future<void> clearVendorPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vendor_pin');
    _vendorPin = '';
    notifyListeners();
  }

  Future<void> clearAdminPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_pin');
    _adminPin = '';
    notifyListeners();
  }

  /// true si el login fue exitoso
  bool loginAs(AppRole targetRole, String pin) {
    if (targetRole == AppRole.admin) {
      // Sin PIN de admin configurado, cualquiera puede entrar
      if (_adminPin.isEmpty || pin == _adminPin) {
        _role = AppRole.admin;
        notifyListeners();
        return true;
      }
      return false;
    } else {
      if (_vendorPin.isNotEmpty && pin == _vendorPin) {
        _role = AppRole.vendor;
        notifyListeners();
        return true;
      }
      return false;
    }
  }

  void setRole(AppRole role) {
    _role = role;
    notifyListeners();
  }

  void logout() {
    _role = AppRole.none;
    notifyListeners();
  }
}
