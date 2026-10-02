import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/hotspot_user.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';
import '../utils/ros_time.dart';

/// Filtros de la lista de usuarios.
enum UserFilter { all, available, unused, expired, disabled }

enum _ExpiredSort { recent, oldest, name }

/// Tiempos disponibles al crear o renovar usuarios.
const List<String> kUserTimes = <String>[
  '5m', '30m', '1h', '2h', '5h', '12h', '1d', '3d', '7d', '30d'
];

String userTimeLabel(String code) {
  const Map<String, String> map = <String, String>{
    '5m': '5 minutos',
    '30m': '30 minutos',
    '1h': '1 hora',
    '2h': '2 horas',
    '5h': '5 horas',
    '12h': '12 horas',
    '1d': '1 día',
    '3d': '3 días',
    '7d': '7 días',
    '30d': '30 días',
  };
  return map[code] ?? code;
}

class UsersTab extends StatefulWidget {
  final UserFilter initialFilter;

  const UsersTab({super.key, this.initialFilter = UserFilter.all});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  List<HotspotUser> _users = <HotspotUser>[];
  bool _loading = true;
  final TextEditingController _searchCtl = TextEditingController();
  late UserFilter _filter;
  _ExpiredSort _expSort = _ExpiredSort.recent;

  // Reloj del router (las marcas de expiración usan su hora)
  DateTime? _routerNow;
  DateTime _loadedAt = DateTime.now();
  bool? _trackerInstalled;
  bool _installing = false;
  Map<String, DateTime> _logTimes = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _load();
  }

  // ─── Carga ────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final List<HotspotUser> users = await api.getUsers();

      DateTime? clock;
      try {
        clock = await api.getRouterClock();
      } catch (_) {
        clock = null;
      }

      bool? tracker;
      try {
        tracker = await api.isExpiryTrackerInstalled();
      } catch (_) {
        tracker = null;
      }

      // Solo se lee el log si hay expirados sin hora exacta registrada
      Map<String, DateTime> logTimes = <String, DateTime>{};
      final bool needLog = users.any(
          (HotspotUser u) => u.isExpired && _validStamp(u.trackedExpiry) == null);
      if (needLog && clock != null) {
        logTimes = await api.getLastLogoutTimes(clock);
      }

      if (!mounted) return;
      setState(() {
        _users = users;
        _routerNow = clock;
        _loadedAt = DateTime.now();
        _trackerInstalled = tracker;
        _logTimes = logTimes;
        _loading = false;
      });
    } on MikroTikException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(e.message, isError: true);
    }
  }

  // ─── Expiración ───────────────────────────────────────────
  /// Descarta fechas de un reloj sin hora (RouterOS arranca en 1970 sin NTP).
  DateTime? _validStamp(DateTime? d) =>
      (d != null && d.year >= 2020) ? d : null;

  bool get _clockOk => _routerNow != null && _routerNow!.year >= 2020;

  /// Hora actual del router estimada (avanza con el reloj del teléfono).
  DateTime? get _nowRouter => _clockOk
      ? _routerNow!.add(DateTime.now().difference(_loadedAt))
      : null;

  ExpiryInfo _expiryOf(HotspotUser u) {
    if (!u.isExpired) return ExpiryInfo.none;
    final DateTime? tracked = _validStamp(u.trackedExpiry);
    if (tracked != null) return ExpiryInfo(tracked, ExpirySource.tracker);
    final DateTime? fromLog = _validStamp(_logTimes[u.name]);
    if (fromLog != null) return ExpiryInfo(fromLog, ExpirySource.log);
    return ExpiryInfo.none;
  }

  Duration? _expiredFor(HotspotUser u) {
    final DateTime? at = _expiryOf(u).at;
    final DateTime? now = _nowRouter;
    if (at == null || now == null) return null;
    final Duration d = now.difference(at);
    return d.isNegative ? Duration.zero : d;
  }

  // ─── Filtros ──────────────────────────────────────────────
  bool _matches(HotspotUser u, UserFilter f) {
    switch (f) {
      case UserFilter.all:
        return true;
      case UserFilter.available:
        return u.isAvailable;
      case UserFilter.unused:
        return u.isUnused && !u.disabled;
      case UserFilter.expired:
        return u.isExpired;
      case UserFilter.disabled:
        return u.disabled;
    }
  }

  int _count(UserFilter f) => _users.where((HotspotUser u) => _matches(u, f)).length;

  List<HotspotUser> get _visible {
    final String q = _searchCtl.text.trim().toLowerCase();
    final List<HotspotUser> list = _users.where((HotspotUser u) {
      if (!_matches(u, _filter)) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.password.toLowerCase().contains(q) ||
          u.cleanComment.toLowerCase().contains(q);
    }).toList();

    if (_filter == UserFilter.expired) {
      list.sort((HotspotUser a, HotspotUser b) {
        if (_expSort == _ExpiredSort.name) return a.name.compareTo(b.name);
        final DateTime? ta = _expiryOf(a).at;
        final DateTime? tb = _expiryOf(b).at;
        // Los de fecha desconocida siempre al final
        if (ta == null && tb == null) return a.name.compareTo(b.name);
        if (ta == null) return 1;
        if (tb == null) return -1;
        return _expSort == _ExpiredSort.recent
            ? tb.compareTo(ta)
            : ta.compareTo(tb);
      });
    }
    return list;
  }

  // ─── Acciones ─────────────────────────────────────────────
  Future<void> _deleteUser(HotspotUser user) async {
    final bool? confirm = await _confirm(
        'Eliminar usuario', 'Eliminar "${user.name}"?', 'Eliminar');
    if (confirm == true && user.id != null) {
      final MikroTikApi? api = context.read<RouterProvider>().api;
      if (api == null) return;
      try {
        await api.deleteUser(user.id!);
        _showSnack('Usuario eliminado');
        _load();
      } on MikroTikException catch (e) {
        _showSnack(e.message, isError: true);
      }
    }
  }

  Future<void> _deleteAllExpired() async {
    final List<HotspotUser> expired =
        _users.where((HotspotUser u) => u.isExpired).toList();
    if (expired.isEmpty) return;
    final bool? confirm = await _confirm(
        'Eliminar expirados',
        'Se eliminarán ${expired.length} usuarios expirados del router.\n'
            'Esta acción no se puede deshacer.',
        'Eliminar ${expired.length}');
    if (confirm != true) return;
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) return;
    setState(() => _loading = true);
    final String? err = await api.deleteUsers(expired);
    if (err != null) {
      _showSnack(err, isError: true);
    } else {
      _showSnack('${expired.length} usuarios eliminados');
    }
    _load();
  }

  Future<void> _resetUptime(HotspotUser user) async {
    if (user.id == null) return;
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) return;
    try {
      await api.resetUserUptime(user.id!, user: user);
      _showSnack('Tiempo reiniciado');
      _load();
    } on MikroTikException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _toggleUser(HotspotUser user) async {
    if (user.id == null) return;
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) return;
    try {
      await api.toggleUser(user.id!, !user.disabled);
      _showSnack(user.disabled ? 'Usuario habilitado' : 'Usuario deshabilitado');
      _load();
    } on MikroTikException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _renewUser(HotspotUser user) async {
    String selected =
        kUserTimes.contains(user.limitUptime) ? user.limitUptime! : '1h';
    final String? time = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDlg) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('Renovar "${user.name}"',
              style: const TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                  'Se pone el contador a cero, se asigna el nuevo tiempo '
                  'y el usuario queda habilitado con la misma contraseña.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: selected,
                dropdownColor: AppTheme.cardLight,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Nuevo tiempo',
                  prefixIcon: Icon(Icons.timer, color: AppTheme.textSecondary),
                ),
                items: kUserTimes
                    .map((String t) => DropdownMenuItem<String>(
                        value: t, child: Text(userTimeLabel(t))))
                    .toList(),
                onChanged: (String? v) => setDlg(() => selected = v!),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Renovar')),
          ],
        ),
      ),
    );
    if (time == null) return;
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) return;
    try {
      await api.renewUser(user, time);
      _showSnack('"${user.name}" renovado por ${userTimeLabel(time)}');
      _load();
    } on MikroTikException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _installTracker() async {
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) return;
    setState(() => _installing = true);
    try {
      await api.installExpiryTracker();
      final int marked = await api.backfillExpiryTags(_users, _logTimes);
      _showSnack(marked > 0
          ? 'Registro activado. $marked expirados anteriores marcados.'
          : 'Registro de expiración activado en el router.');
      if (mounted) setState(() => _installing = false);
      _load();
    } on MikroTikException catch (e) {
      if (mounted) setState(() => _installing = false);
      _showSnack(e.message, isError: true);
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('$label copiado');
  }

  Future<bool?> _confirm(String title, String body, String action) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        content:
            Text(body, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action, style: const TextStyle(color: AppTheme.error))),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      duration: Duration(seconds: isError ? 6 : 2),
    ));
  }

  // ─── Detalle ──────────────────────────────────────────────
  void _showDetails(HotspotUser u) {
    final ExpiryInfo exp = _expiryOf(u);
    final Duration? ago = _expiredFor(u);
    final _Status st = _statusOf(u);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (BuildContext ctx, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: st.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(st.icon, color: st.color, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(u.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      Text(st.label,
                          style: TextStyle(color: st.color, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            if (u.isExpired) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ago != null
                          ? 'Expirado hace ${RosTime.formatAgo(ago)}'
                          : 'Expirado — hora desconocida',
                      style: const TextStyle(
                          color: AppTheme.warning,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exp.at != null
                          ? 'El ${RosTime.formatDateTime(exp.at!)} · ${_sourceLabel(exp.source)}'
                          : _sourceLabel(exp.source),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _detailRow('Usuario', u.name,
                onCopy: () => _copy(u.name, 'Usuario')),
            _detailRow('Contraseña', u.password.isEmpty ? '(vacía)' : u.password,
                onCopy: u.password.isEmpty
                    ? null
                    : () => _copy(u.password, 'Contraseña')),
            _detailRow('Tiempo comprado',
                u.hasLimit ? RosTime.formatDuration(u.limitDuration) : 'Ilimitado'),
            _detailRow('Tiempo usado', RosTime.formatDuration(u.usedDuration)),
            if (!u.isExpired && u.hasLimit)
              _detailRow('Tiempo restante', u.remainingTime),
            _detailRow('Descargado', RosTime.formatBytes(u.bytesOut)),
            _detailRow('Subido', RosTime.formatBytes(u.bytesIn)),
            _detailRow('Tráfico total', RosTime.formatBytes(u.totalBytes)),
            _detailRow('Perfil', u.profile),
            _detailRow('Servidor', u.server),
            if (u.macAddress != null && u.macAddress!.isNotEmpty)
              _detailRow('MAC fija', u.macAddress!),
            if (u.cleanComment.isNotEmpty)
              _detailRow('Comentario', u.cleanComment),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      u.isExpired ? _renewUser(u) : _resetUptime(u);
                    },
                    icon: Icon(u.isExpired ? Icons.autorenew : Icons.restore),
                    label: Text(u.isExpired ? 'Renovar' : 'Reiniciar tiempo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteUser(u);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {VoidCallback? onCopy}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ),
          if (onCopy != null)
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded,
                    size: 16, color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  String _sourceLabel(ExpirySource s) {
    switch (s) {
      case ExpirySource.tracker:
        return 'hora exacta registrada por el router';
      case ExpirySource.log:
        return 'aproximado según el log del router';
      case ExpirySource.unknown:
        return 'Expiró antes de activar el registro y ya no está en el log';
    }
  }

  _Status _statusOf(HotspotUser u) {
    if (u.disabled) {
      return const _Status('Deshabilitado', AppTheme.error, Icons.block);
    }
    if (u.isExpired) {
      return const _Status('Expirado', AppTheme.warning, Icons.timer_off);
    }
    if (u.isUnused) {
      return const _Status('Sin usar', AppTheme.accent, Icons.fiber_new);
    }
    return const _Status('Activo', AppTheme.success, Icons.person);
  }

  // ─── Crear usuario ────────────────────────────────────────
  void _showAddDialog() {
    final RouterProvider prov = context.read<RouterProvider>();
    final TextEditingController nameCtl = TextEditingController();
    final TextEditingController passCtl = TextEditingController();
    String selectedTime = '1h';
    String selectedServer = prov.selectedServer;
    String selectedProfile = prov.selectedProfile;

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDlgState) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: const Text('Nuevo Usuario',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameCtl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon:
                        Icon(Icons.person, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedTime,
                  dropdownColor: AppTheme.cardLight,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Tiempo límite',
                    prefixIcon: Icon(Icons.timer, color: AppTheme.textSecondary),
                  ),
                  items: kUserTimes
                      .map((String t) => DropdownMenuItem<String>(
                          value: t, child: Text(userTimeLabel(t))))
                      .toList(),
                  onChanged: (String? v) => setDlgState(() => selectedTime = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: prov.servers.contains(selectedServer)
                      ? selectedServer
                      : prov.servers.first,
                  dropdownColor: AppTheme.cardLight,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Servidor hotspot',
                    prefixIcon: Icon(Icons.dns, color: AppTheme.textSecondary),
                  ),
                  items: prov.servers
                      .map((String sv) =>
                          DropdownMenuItem<String>(value: sv, child: Text(sv)))
                      .toList(),
                  onChanged: (String? v) =>
                      setDlgState(() => selectedServer = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: prov.profiles.contains(selectedProfile)
                      ? selectedProfile
                      : prov.profiles.first,
                  dropdownColor: AppTheme.cardLight,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Perfil',
                    prefixIcon: Icon(Icons.speed, color: AppTheme.textSecondary),
                  ),
                  items: prov.profiles
                      .map((String pf) =>
                          DropdownMenuItem<String>(value: pf, child: Text(pf)))
                      .toList(),
                  onChanged: (String? v) =>
                      setDlgState(() => selectedProfile = v!),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty ||
                    passCtl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx);
                final MikroTikApi? api = context.read<RouterProvider>().api;
                if (api == null) {
                  _showSnack('Sin conexion al router', isError: true);
                  return;
                }
                final HotspotUser user = HotspotUser(
                  name: nameCtl.text.trim(),
                  password: passCtl.text.trim(),
                  server: selectedServer,
                  profile: selectedProfile,
                  limitUptime: selectedTime,
                );
                try {
                  await api.addUser(user);
                  _showSnack('Usuario creado');
                  _load();
                } on MikroTikException catch (e) {
                  _showSnack(e.message, isError: true);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final List<HotspotUser> visible = _loading ? <HotspotUser>[] : _visible;
    final bool expiredMode = _filter == UserFilter.expired;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: expiredMode
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.person_add),
            ),
      body: Column(
        children: <Widget>[
          // Búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar usuario, contraseña o comentario...',
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.textSecondary),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppTheme.textSecondary),
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() {});
                        })
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Filtros
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: <Widget>[
                _filterChip(UserFilter.all, 'Todos', AppTheme.primary),
                _filterChip(UserFilter.available, 'Disponibles', AppTheme.success),
                _filterChip(UserFilter.unused, 'Sin usar', AppTheme.accent),
                _filterChip(UserFilter.expired, 'Expirados', AppTheme.warning),
                _filterChip(UserFilter.disabled, 'Deshabilitados', AppTheme.error),
              ],
            ),
          ),
          // Contador + acciones
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: Row(
              children: <Widget>[
                Text('${visible.length} usuarios',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const Spacer(),
                if (expiredMode) ...<Widget>[
                  PopupMenuButton<_ExpiredSort>(
                    tooltip: 'Ordenar',
                    color: AppTheme.card,
                    icon: const Icon(Icons.sort_rounded,
                        color: AppTheme.textSecondary, size: 20),
                    onSelected: (_ExpiredSort s) =>
                        setState(() => _expSort = s),
                    itemBuilder: (_) => <PopupMenuEntry<_ExpiredSort>>[
                      _sortItem(_ExpiredSort.recent, 'Expiró más reciente'),
                      _sortItem(_ExpiredSort.oldest, 'Más tiempo expirado'),
                      _sortItem(_ExpiredSort.name, 'Nombre'),
                    ],
                  ),
                  if (_count(UserFilter.expired) > 0)
                    TextButton.icon(
                      onPressed: _deleteAllExpired,
                      icon: const Icon(Icons.delete_sweep,
                          color: AppTheme.error, size: 18),
                      label: const Text('Borrar todos',
                          style: TextStyle(color: AppTheme.error, fontSize: 12)),
                    ),
                ],
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
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      children: <Widget>[
                        if (expiredMode) ..._expiredHeader(),
                        if (visible.isEmpty) _emptyState(),
                        ...visible.map((HotspotUser u) => expiredMode
                            ? _ExpiredUserCard(
                                user: u,
                                expiry: _expiryOf(u),
                                expiredFor: _expiredFor(u),
                                onTap: () => _showDetails(u),
                                onRenew: () => _renewUser(u),
                                onDelete: () => _deleteUser(u),
                                onCopy: () => _copy(
                                    'Usuario: ${u.name}\nContraseña: ${u.password}',
                                    'Credenciales'),
                              )
                            : _UserCard(
                                user: u,
                                status: _statusOf(u),
                                expiredFor: _expiredFor(u),
                                onTap: () => _showDetails(u),
                                onDelete: () => _deleteUser(u),
                                onReset: () => _resetUptime(u),
                                onToggle: () => _toggleUser(u),
                                onRenew: () => _renewUser(u),
                              )),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _expiredHeader() {
    final List<HotspotUser> expired =
        _users.where((HotspotUser u) => u.isExpired).toList();
    final int total =
        expired.fold<int>(0, (int s, HotspotUser u) => s + u.totalBytes);
    final Duration timeSold = expired.fold<Duration>(
        Duration.zero, (Duration s, HotspotUser u) => s + u.limitDuration);
    final int last24 = expired.where((HotspotUser u) {
      final Duration? d = _expiredFor(u);
      return d != null && d.inHours < 24;
    }).length;

    return <Widget>[
      // Resumen
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[AppTheme.warning.withOpacity(0.15), AppTheme.card],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
        ),
        child: Row(
          children: <Widget>[
            _summaryItem('${expired.length}', 'Expirados'),
            _summaryItem('$last24', 'Últimas 24h'),
            _summaryItem(RosTime.formatDuration(timeSold), 'Tiempo vendido'),
            _summaryItem(RosTime.formatBytes(total), 'Tráfico'),
          ],
        ),
      ),
      // Reloj del router sin hora
      if (!_clockOk)
        _banner(
          icon: Icons.schedule,
          color: AppTheme.error,
          text: 'El reloj del router no tiene la hora correcta, no se puede '
              'calcular cuánto tiempo llevan expirados. Activa NTP en el router:\n'
              '/system ntp client set enabled=yes servers=pool.ntp.org',
        ),
      // Registro de expiración sin instalar
      if (_trackerInstalled == false)
        _banner(
          icon: Icons.history_toggle_off,
          color: AppTheme.primary,
          text: 'Activa el registro de expiración para guardar la hora exacta '
              'en que expira cada usuario. Crea en el router el scheduler '
              '"${MikroTikApi.expiryScheduler}" (cada 1 min). '
              'Sin él, la hora sale del log y se pierde al reiniciar.',
          action: _installing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary))
              : TextButton(
                  onPressed: _installTracker, child: const Text('Activar')),
        ),
    ];
  }

  Widget _summaryItem(String value, String label) {
    return Expanded(
      child: Column(
        children: <Widget>[
          FittedBox(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.warning,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _banner(
      {required IconData icon,
      required Color color,
      required String text,
      Widget? action}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, height: 1.35)),
          ),
          if (action != null) ...<Widget>[const SizedBox(width: 6), action],
        ],
      ),
    );
  }

  Widget _emptyState() {
    final String text = _filter == UserFilter.expired
        ? 'No hay usuarios expirados'
        : 'Sin usuarios en este filtro';
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: <Widget>[
          Icon(Icons.inbox_outlined,
              size: 48, color: AppTheme.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _filterChip(UserFilter f, String label, Color color) {
    final bool selected = _filter == f;
    final int n = _count(f);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = f),
        backgroundColor: AppTheme.card,
        selectedColor: color.withOpacity(0.2),
        side: BorderSide(color: selected ? color : AppTheme.divider),
        label: Text('$label  $n',
            style: TextStyle(
                color: selected ? color : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
      ),
    );
  }

  PopupMenuItem<_ExpiredSort> _sortItem(_ExpiredSort s, String label) {
    final bool selected = _expSort == s;
    return PopupMenuItem<_ExpiredSort>(
      value: s,
      child: Row(
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          if (selected) ...<Widget>[
            const Spacer(),
            const Icon(Icons.check, color: AppTheme.primary, size: 16),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }
}

class _Status {
  final String label;
  final Color color;
  final IconData icon;

  const _Status(this.label, this.color, this.icon);
}

// ─── Tarjeta de usuario expirado ────────────────────────────
class _ExpiredUserCard extends StatelessWidget {
  final HotspotUser user;
  final ExpiryInfo expiry;
  final Duration? expiredFor;
  final VoidCallback onTap;
  final VoidCallback onRenew;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  const _ExpiredUserCard({
    required this.user,
    required this.expiry,
    required this.expiredFor,
    required this.onTap,
    required this.onRenew,
    required this.onDelete,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final String when = expiry.at != null
        ? RosTime.formatDateTime(expiry.at!)
        : 'Fecha desconocida';
    final String source = switch (expiry.source) {
      ExpirySource.tracker => 'exacto',
      ExpirySource.log => 'aprox. log',
      ExpirySource.unknown => '',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.timer_off,
                        color: AppTheme.warning, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(user.name,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.vpn_key,
                                color: AppTheme.accent, size: 12),
                            const SizedBox(width: 4),
                            Text(user.password.isEmpty ? '(sin contraseña)' : user.password,
                                style: const TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Tiempo expirado
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        const Text('expirado hace',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 9)),
                        Text(
                            expiredFor != null
                                ? RosTime.formatAgo(expiredFor!)
                                : '—',
                            style: const TextStyle(
                                color: AppTheme.warning,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Icon(Icons.event_busy,
                      color: AppTheme.textSecondary, size: 13),
                  const SizedBox(width: 5),
                  Text('Expiró: $when',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12)),
                  if (source.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Text('($source)',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _chip(Icons.timer, 'Plan ${RosTime.formatDuration(user.limitDuration)}'),
                  _chip(Icons.hourglass_bottom,
                      'Usó ${RosTime.formatDuration(user.usedDuration)}'),
                  _chip(Icons.download, RosTime.formatBytes(user.bytesOut)),
                  _chip(Icons.upload, RosTime.formatBytes(user.bytesIn)),
                  _chip(Icons.speed, user.profile),
                  if (user.disabled) _chip(Icons.block, 'Deshabilitado'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _action(Icons.copy_rounded, 'Copiar', AppTheme.textSecondary,
                      onCopy),
                  _action(Icons.autorenew, 'Renovar', AppTheme.primary, onRenew),
                  _action(
                      Icons.delete_outline, 'Eliminar', AppTheme.error, onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: AppTheme.textSecondary, size: 12),
          const SizedBox(width: 4),
          Text(text,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 34),
      ),
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

// ─── Tarjeta de usuario (resto de filtros) ──────────────────
class _UserCard extends StatelessWidget {
  final HotspotUser user;
  final _Status status;
  final Duration? expiredFor;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onReset;
  final VoidCallback onToggle;
  final VoidCallback onRenew;

  const _UserCard({
    required this.user,
    required this.status,
    required this.expiredFor,
    required this.onTap,
    required this.onDelete,
    required this.onReset,
    required this.onToggle,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor = status.color;
    String statusText = status.label;
    if (user.isExpired && !user.disabled && expiredFor != null) {
      statusText = 'Expirado hace ${RosTime.formatAgo(expiredFor!)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(status.icon, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(user.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.vpn_key,
                                color: AppTheme.accent, size: 11),
                            const SizedBox(width: 3),
                            Text(user.password,
                                style: const TextStyle(
                                    color: AppTheme.accent, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(statusText,
                                style: TextStyle(
                                    color: statusColor, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: AppTheme.cardLight,
                    icon: const Icon(Icons.more_vert,
                        color: AppTheme.textSecondary, size: 20),
                    onSelected: (String v) {
                      switch (v) {
                        case 'renew':
                          onRenew();
                          break;
                        case 'reset':
                          onReset();
                          break;
                        case 'toggle':
                          onToggle();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (user.isExpired)
                        const PopupMenuItem<String>(
                            value: 'renew',
                            child: Row(children: <Widget>[
                              Icon(Icons.autorenew,
                                  color: AppTheme.primary, size: 18),
                              SizedBox(width: 8),
                              Text('Renovar',
                                  style:
                                      TextStyle(color: AppTheme.textPrimary))
                            ])),
                      const PopupMenuItem<String>(
                          value: 'reset',
                          child: Row(children: <Widget>[
                            Icon(Icons.restore,
                                color: AppTheme.primary, size: 18),
                            SizedBox(width: 8),
                            Text('Reiniciar tiempo',
                                style: TextStyle(color: AppTheme.textPrimary))
                          ])),
                      PopupMenuItem<String>(
                          value: 'toggle',
                          child: Row(children: <Widget>[
                            Icon(user.disabled ? Icons.play_arrow : Icons.pause,
                                color: AppTheme.warning, size: 18),
                            const SizedBox(width: 8),
                            Text(user.disabled ? 'Habilitar' : 'Deshabilitar',
                                style: const TextStyle(
                                    color: AppTheme.textPrimary))
                          ])),
                      const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(children: <Widget>[
                            Icon(Icons.delete, color: AppTheme.error, size: 18),
                            SizedBox(width: 8),
                            Text('Eliminar',
                                style: TextStyle(color: AppTheme.error))
                          ])),
                    ],
                  ),
                ],
              ),
              if (user.hasLimit) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    const Icon(Icons.timer,
                        color: AppTheme.textSecondary, size: 14),
                    const SizedBox(width: 6),
                    Text('Restante: ${user.remainingTime}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Text('Límite: ${user.limitUptime}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: user.usagePercent,
                    minHeight: 5,
                    backgroundColor: AppTheme.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        user.isExpired
                            ? AppTheme.warning
                            : (user.usagePercent > 0.8
                                ? AppTheme.error
                                : AppTheme.primary)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}
