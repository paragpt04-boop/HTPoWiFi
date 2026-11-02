import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/accounting_entry.dart';
import '../models/hotspot_user.dart';
import '../models/router_config.dart';

/// Registro local de primeras fechas de uso anotadas por el router.
class AccountingProvider extends ChangeNotifier {
  static const String _storageKey = 'accounting_v1';

  final List<AccountingEntry> _entries = <AccountingEntry>[];
  final Map<String, AccountingSettings> _settings =
      <String, AccountingSettings>{};
  final Map<String, AccountingOverrides> _overrides =
      <String, AccountingOverrides>{};
  Future<void>? _loading;
  Future<void> _pendingWrite = Future<void>.value();
  String? _loadError;

  String? get loadError => _loadError;

  static String routerKey(RouterConfig config) =>
      '${config.useSsl ? 'https' : 'http'}://${config.host}:${config.port}';

  List<AccountingEntry> entriesFor(String router) => _entries
      .where((AccountingEntry entry) => entry.routerKey == router)
      .toList()
    ..sort((AccountingEntry a, AccountingEntry b) =>
        b.firstUsedAt.compareTo(a.firstUsedAt));

  AccountingSettings settingsFor(String router) =>
      _settings[router] ?? const AccountingSettings();

  AccountingOverrides overridesFor(String router, DateTime day) =>
      _overrides[_dayKey(router, day)] ?? const AccountingOverrides();

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final Map<String, dynamic> data =
          (jsonDecode(raw) as Map).cast<String, dynamic>();
      _entries.addAll((data['entries'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((Map value) =>
              AccountingEntry.fromJson(value.cast<String, dynamic>())));
      final Map settings = data['settings'] as Map? ?? <String, dynamic>{};
      for (final MapEntry entry in settings.entries) {
        _settings[entry.key.toString()] = AccountingSettings.fromJson(
            (entry.value as Map).cast<String, dynamic>());
      }
      final Map overrides = data['overrides'] as Map? ?? <String, dynamic>{};
      for (final MapEntry entry in overrides.entries) {
        _overrides[entry.key.toString()] = AccountingOverrides.fromJson(
            (entry.value as Map).cast<String, dynamic>());
      }
      notifyListeners();
    } catch (_) {
      _loadError = 'No se pudo leer el historial local de Contabilidad.';
      notifyListeners();
    }
  }

  Future<void> _save() async {
    if (_loadError != null) throw StateError(_loadError!);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool saved = await prefs.setString(
        _storageKey,
        jsonEncode(<String, dynamic>{
          'entries': _entries.map((AccountingEntry e) => e.toJson()).toList(),
          'settings': _settings.map((String key, AccountingSettings value) =>
              MapEntry<String, dynamic>(key, value.toJson())),
          'overrides': _overrides.map((String key, AccountingOverrides value) =>
              MapEntry<String, dynamic>(key, value.toJson())),
        }));
    if (!saved) throw StateError('No se pudo guardar Contabilidad.');
    notifyListeners();
  }

  Future<T> _write<T>(Future<T> Function() action) {
    final Future<T> next = _pendingWrite.then((_) => action());
    _pendingWrite = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  /// Guarda una sola vez cada primer uso marcado por el router, incluso si la
  /// aplicación estuvo cerrada al ocurrir.
  Future<int> observeUsers(RouterConfig config, List<HotspotUser> users) async {
    await load();
    return _write(() async {
      if (_loadError != null) throw StateError(_loadError!);
      final String router = routerKey(config);
      final AccountingSettings settings = settingsFor(router);
      final Set<String> existingIds =
          _entries.map((AccountingEntry entry) => entry.id).toSet();
      final List<AccountingEntry> fresh = <AccountingEntry>[];

      for (final HotspotUser user in users) {
        if (user.id == null) continue;
        final DateTime? firstUse = user.trackedFirstUse;
        if (firstUse == null || firstUse.year < 2020) continue;
        final String id = '$router|${user.id}|${firstUse.toIso8601String()}';
        if (!existingIds.add(id)) continue;
        fresh.add(AccountingEntry(
          id: id,
          routerKey: router,
          userName: user.name,
          profile: user.profile,
          firstUsedAt: firstUse,
          hours: user.limitDuration.inSeconds / 3600,
          hourlyRate: settings.rateFor(user.profile),
        ));
      }

      if (fresh.isEmpty) return 0;
      _entries.addAll(fresh);
      try {
        await _save();
      } catch (_) {
        _entries.removeWhere((AccountingEntry e) =>
            fresh.any((AccountingEntry added) => added.id == e.id));
        rethrow;
      }
      return fresh.length;
    });
  }

  Future<void> updateSettings(
      String router, AccountingSettings settings) async {
    await load();
    await _write(() async {
      if (_loadError != null) throw StateError(_loadError!);
      final AccountingSettings? old = _settings[router];
      _settings[router] = settings;
      try {
        await _save();
      } catch (_) {
        if (old == null) {
          _settings.remove(router);
        } else {
          _settings[router] = old;
        }
        rethrow;
      }
    });
  }

  Future<void> updateEntry(AccountingEntry updated) async {
    await load();
    await _write(() async {
      if (_loadError != null) throw StateError(_loadError!);
      final int index =
          _entries.indexWhere((AccountingEntry e) => e.id == updated.id);
      if (index < 0) return;
      final AccountingEntry old = _entries[index];
      _entries[index] = updated;
      try {
        await _save();
      } catch (_) {
        _entries[index] = old;
        rethrow;
      }
    });
  }

  Future<void> updateOverrides(
      String router, DateTime day, AccountingOverrides overrides) async {
    await load();
    await _write(() async {
      if (_loadError != null) throw StateError(_loadError!);
      final String key = _dayKey(router, day);
      final AccountingOverrides? old = _overrides[key];
      _overrides[key] = overrides;
      try {
        await _save();
      } catch (_) {
        if (old == null) {
          _overrides.remove(key);
        } else {
          _overrides[key] = old;
        }
        rethrow;
      }
    });
  }

  static DateTime dayStart(DateTime at, int startMinute) {
    final DateTime start = DateTime(
        at.year, at.month, at.day, startMinute ~/ 60, startMinute % 60);
    return at.isBefore(start)
        ? DateTime(
            at.year, at.month, at.day - 1, startMinute ~/ 60, startMinute % 60)
        : start;
  }

  static DateTime rangeStart(DateTime now, int startMinute, int days) {
    final DateTime today = dayStart(now, startMinute);
    return DateTime(today.year, today.month, today.day - (days - 1), today.hour,
        today.minute);
  }

  static String _dayKey(String router, DateTime day) =>
      '$router|${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}|'
      '${day.hour.toString().padLeft(2, '0')}:'
      '${day.minute.toString().padLeft(2, '0')}';
}
