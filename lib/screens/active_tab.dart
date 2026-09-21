import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/active_session.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';

enum _SortMode { username, uptime, trafficIn }

class ActiveTab extends StatefulWidget {
  const ActiveTab({super.key});

  @override
  State<ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends State<ActiveTab> {
  List<ActiveSession> _sessions = [];
  Map<String, String> _passwordMap = {};
  bool _loading = true;
  Timer? _timer;
  _SortMode _sortMode = _SortMode.username;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<RouterProvider>().api;
    if (api == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // Lanza ambas peticiones en paralelo sin esperar una antes que la otra
      final sessionsFuture = api.getActiveSessions();
      final passwordsFuture = api.getUserPasswordMap();
      final sessions = await sessionsFuture;
      final passwords = await passwordsFuture;
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _passwordMap = passwords;
        _loading = false;
        _applySort();
      });
    } on MikroTikException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.message, isError: true);
    }
  }

  void _applySort() {
    switch (_sortMode) {
      case _SortMode.username:
        _sessions.sort((a, b) => a.user.compareTo(b.user));
        break;
      case _SortMode.uptime:
        // Uptime viene como "1h23m45s" — ordenar lexicográficamente por longitud desc
        // (más largo = más tiempo conectado)
        _sessions.sort((a, b) {
          final la = a.uptime.length;
          final lb = b.uptime.length;
          if (la != lb) return lb.compareTo(la);
          return b.uptime.compareTo(a.uptime);
        });
        break;
      case _SortMode.trafficIn:
        _sessions.sort((a, b) {
          // trafficIn como "12.5 MiB" — ordenar por longitud y valor
          return _parseTraffic(b.trafficIn)
              .compareTo(_parseTraffic(a.trafficIn));
        });
        break;
    }
  }

  /// Convierte "12.5 MiB" / "345 KiB" / "1.2 GiB" a bytes aproximados para ordenar.
  double _parseTraffic(String t) {
    final parts = t.trim().split(' ');
    if (parts.length < 2) return 0;
    final num = double.tryParse(parts[0]) ?? 0;
    final unit = parts[1].toUpperCase();
    if (unit.startsWith('G')) return num * 1e9;
    if (unit.startsWith('M')) return num * 1e6;
    if (unit.startsWith('K')) return num * 1e3;
    return num;
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      duration: Duration(seconds: isError ? 6 : 2),
    ));
  }

  Future<void> _disconnect(ActiveSession session) async {
    if (session.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Desconectar',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Desconectar a "${session.user}"?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desconectar',
                  style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      final api = context.read<RouterProvider>().api;
      if (api == null) return;
      try {
        await api.disconnectSession(session.id!);
        _snack('Usuario desconectado');
        _load();
      } on MikroTikException catch (e) {
        _snack(e.message, isError: true);
      }
    }
  }

  Future<void> _disconnectAll() async {
    if (_sessions.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Desconectar todos',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Desconectar ${_sessions.length} sesiones activas?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desconectar todos',
                  style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      final api = context.read<RouterProvider>().api;
      if (api == null) return;
      String? err;
      for (final s in _sessions) {
        if (s.id == null) continue;
        try {
          await api.disconnectSession(s.id!);
        } on MikroTikException catch (e) {
          err ??= e.message;
        }
      }
      if (err != null) _snack(err, isError: true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header con contador, sort y acciones
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi, color: AppTheme.success, size: 16),
                    const SizedBox(width: 6),
                    Text('${_sessions.length} activos',
                        style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Spacer(),
              // Sort picker
              PopupMenuButton<_SortMode>(
                initialValue: _sortMode,
                tooltip: 'Ordenar por',
                color: AppTheme.card,
                icon: const Icon(Icons.sort_rounded,
                    color: AppTheme.textSecondary, size: 20),
                onSelected: (mode) {
                  setState(() {
                    _sortMode = mode;
                    _applySort();
                  });
                },
                itemBuilder: (_) => [
                  _sortItem(_SortMode.username, Icons.sort_by_alpha, 'Nombre'),
                  _sortItem(_SortMode.uptime, Icons.access_time, 'Tiempo'),
                  _sortItem(_SortMode.trafficIn, Icons.download, 'Tráfico'),
                ],
              ),
              if (_sessions.isNotEmpty)
                TextButton.icon(
                  onPressed: _disconnectAll,
                  icon: const Icon(Icons.wifi_off,
                      color: AppTheme.error, size: 16),
                  label: const Text('Cortar todos',
                      style: TextStyle(color: AppTheme.error, fontSize: 12)),
                ),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: AppTheme.textSecondary, size: 20),
                onPressed: _load,
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off,
                              size: 48,
                              color: AppTheme.textSecondary.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          const Text('Sin sesiones activas',
                              style:
                                  TextStyle(color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _sessions.length,
                        itemBuilder: (_, i) {
                          final s = _sessions[i];
                          final password = _passwordMap[s.user] ?? '';
                          return _SessionCard(
                            session: s,
                            password: password,
                            onDisconnect: () => _disconnect(s),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  PopupMenuItem<_SortMode> _sortItem(
      _SortMode mode, IconData icon, String label) {
    final selected = _sortMode == mode;
    return PopupMenuItem<_SortMode>(
      value: mode,
      child: Row(
        children: [
          Icon(icon,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
              size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textPrimary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal)),
          if (selected) ...[
            const Spacer(),
            const Icon(Icons.check, color: AppTheme.primary, size: 16),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _SessionCard extends StatelessWidget {
  final ActiveSession session;
  final String password;
  final VoidCallback onDisconnect;

  const _SessionCard({
    required this.session,
    required this.password,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person,
                    color: AppTheme.success, size: 24),
              ),
              const SizedBox(width: 12),
              // Usuario + contraseña
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.user,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.vpn_key,
                            color: AppTheme.accent, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          password.isEmpty ? '(sin contraseña)' : password,
                          style: TextStyle(
                            color: password.isEmpty
                                ? AppTheme.textSecondary
                                : AppTheme.accent,
                            fontSize: 12,
                            fontWeight: password.isEmpty
                                ? FontWeight.normal
                                : FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Botón desconectar
              IconButton(
                onPressed: onDisconnect,
                icon: const Icon(Icons.power_settings_new,
                    color: AppTheme.error, size: 22),
                tooltip: 'Desconectar',
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.error.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Info chips — segunda fila
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _infoChip(Icons.access_time, session.uptime),
              _infoChip(Icons.language, session.address),
              _infoChip(Icons.download, session.trafficIn),
              _infoChip(Icons.upload, session.trafficOut),
            ],
          ),
          const SizedBox(height: 6),
          Text(session.macAddress,
              style: TextStyle(
                  color: AppTheme.textSecondary.withOpacity(0.6),
                  fontSize: 10,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 12),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
