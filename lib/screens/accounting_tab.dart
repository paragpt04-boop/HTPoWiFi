import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/accounting_entry.dart';
import '../providers/accounting_provider.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';

class AccountingTab extends StatefulWidget {
  final Future<void> Function() onRefresh;

  const AccountingTab({super.key, required this.onRefresh});

  @override
  State<AccountingTab> createState() => _AccountingTabState();
}

class _AccountingTabState extends State<AccountingTab> {
  int _days = 1;
  int _periodOffset = 0;
  bool _busy = false;
  bool? _trackerInstalled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final RouterProvider router = context.read<RouterProvider>();
    final MikroTikApi? api = router.api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await context.read<AccountingProvider>().load();
      await widget.onRefresh();
      final bool installed = await api.isFirstUseTrackerInstalled();
      if (mounted) setState(() => _trackerInstalled = installed);
    } on MikroTikException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activateTracker() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Activar registro de primer uso'),
        content: const Text(
          'La app añadirá un registro independiente en MikroTik. '
          'Los usuarios que ya consumieron tiempo se marcarán como anteriores '
          'y no se cobrarán de nuevo. Los primeros usos futuros quedarán '
          'fechados en el router aunque el teléfono esté apagado.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Activar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final MikroTikApi? api = context.read<RouterProvider>().api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.installFirstUseTracker();
      if (!mounted) return;
      setState(() => _trackerInstalled = true);
      _snack('Registro de primer uso activado');
      await _refresh();
    } on MikroTikException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double? _decimal(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
    ));
  }

  Future<void> _editSettings(
      String routerKey, AccountingSettings current) async {
    final TextEditingController defaultCtl =
        TextEditingController(text: current.defaultRate.toStringAsFixed(2));
    final TextEditingController premiumCtl =
        TextEditingController(text: current.premiumRate.toStringAsFixed(2));
    TimeOfDay time = TimeOfDay(
        hour: current.startMinute ~/ 60, minute: current.startMinute % 60);
    final AccountingSettings? result = await showDialog<AccountingSettings>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter update) => AlertDialog(
          title: const Text('Precios y cierre diario'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              TextField(
                controller: defaultCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Default · pesos por hora'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: premiumCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Premium · pesos por hora'),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('Comienzo del día contable'),
                subtitle: Text(time.format(ctx)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final TimeOfDay? picked =
                      await showTimePicker(context: ctx, initialTime: time);
                  if (picked != null) update(() => time = picked);
                },
              ),
            ]),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                final double? standard = _decimal(defaultCtl.text);
                final double? premium = _decimal(premiumCtl.text);
                if (standard == null ||
                    premium == null ||
                    !standard.isFinite ||
                    !premium.isFinite ||
                    standard < 0 ||
                    premium < 0) {
                  _snack('Introduce precios válidos', error: true);
                  return;
                }
                Navigator.pop(
                    ctx,
                    AccountingSettings(
                      defaultRate: standard,
                      premiumRate: premium,
                      startMinute: time.hour * 60 + time.minute,
                    ));
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    defaultCtl.dispose();
    premiumCtl.dispose();
    if (result == null || !mounted) return;
    await context.read<AccountingProvider>().updateSettings(routerKey, result);
  }

  Future<void> _editEntry(AccountingEntry entry) async {
    final TextEditingController hoursCtl =
        TextEditingController(text: entry.hours.toStringAsFixed(2));
    final TextEditingController rateCtl =
        TextEditingController(text: entry.hourlyRate.toStringAsFixed(2));
    final AccountingEntry? updated = await showDialog<AccountingEntry>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Corregir ${entry.userName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(
            controller: hoursCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Horas del usuario'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: rateCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Pesos por hora'),
          ),
        ]),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final double? hours = _decimal(hoursCtl.text);
              final double? rate = _decimal(rateCtl.text);
              if (hours == null ||
                  rate == null ||
                  !hours.isFinite ||
                  !rate.isFinite ||
                  hours < 0 ||
                  rate < 0) {
                _snack('Introduce horas y precio válidos', error: true);
                return;
              }
              Navigator.pop(
                  ctx, entry.copyWith(hours: hours, hourlyRate: rate));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    hoursCtl.dispose();
    rateCtl.dispose();
    if (updated == null || !mounted) return;
    await context.read<AccountingProvider>().updateEntry(updated);
  }

  Future<void> _editDay(String router, _AccountingDay day) async {
    final TextEditingController moneyCtl = TextEditingController(
        text: day.overrides.money?.toStringAsFixed(2) ?? '');
    final TextEditingController usersCtl =
        TextEditingController(text: day.overrides.users?.toString() ?? '');
    final TextEditingController hoursCtl = TextEditingController(
        text: day.overrides.hours?.toStringAsFixed(2) ?? '');
    final AccountingOverrides? result = await showDialog<AccountingOverrides>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Corregir totales del día'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Text('Deja un campo vacío para volver al cálculo automático.',
                style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
                controller: moneyCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Dinero total')),
            const SizedBox(height: 12),
            TextField(
                controller: usersCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Usuarios total')),
            const SizedBox(height: 12),
            TextField(
                controller: hoursCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Horas total')),
          ]),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final double? money =
                  moneyCtl.text.trim().isEmpty ? null : _decimal(moneyCtl.text);
              final int? users = usersCtl.text.trim().isEmpty
                  ? null
                  : int.tryParse(usersCtl.text.trim());
              final double? hours =
                  hoursCtl.text.trim().isEmpty ? null : _decimal(hoursCtl.text);
              if ((moneyCtl.text.trim().isNotEmpty && money == null) ||
                  (usersCtl.text.trim().isNotEmpty && users == null) ||
                  (hoursCtl.text.trim().isNotEmpty && hours == null) ||
                  (money != null && (!money.isFinite || money < 0)) ||
                  (users != null && users < 0) ||
                  (hours != null && (!hours.isFinite || hours < 0))) {
                _snack('Introduce totales válidos', error: true);
                return;
              }
              Navigator.pop(
                  ctx,
                  AccountingOverrides(
                      money: money, users: users, hours: hours));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    moneyCtl.dispose();
    usersCtl.dispose();
    hoursCtl.dispose();
    if (result == null || !mounted) return;
    await context
        .read<AccountingProvider>()
        .updateOverrides(router, day.start, result);
  }

  @override
  Widget build(BuildContext context) {
    final RouterProvider router = context.watch<RouterProvider>();
    final AccountingProvider accounting = context.watch<AccountingProvider>();
    final config = router.config;
    if (config == null) return const SizedBox.shrink();
    final String routerKey = AccountingProvider.routerKey(config);
    final AccountingSettings settings = accounting.settingsFor(routerKey);
    final DateTime now = DateTime.now();
    final DateTime first = AccountingProvider.rangeStart(
        now, settings.startMinute, _days + _periodOffset);
    final DateTime periodEnd = DateTime(
        first.year, first.month, first.day + _days, first.hour, first.minute);
    final DateTime visibleEnd = periodEnd.isAfter(now) ? now : periodEnd;
    final List<AccountingEntry> all = accounting.entriesFor(routerKey);
    final List<_AccountingDay> days = <_AccountingDay>[];
    for (int i = 0; i < _days; i++) {
      final DateTime start = DateTime(
          first.year, first.month, first.day + i, first.hour, first.minute);
      final DateTime end = DateTime(
          start.year, start.month, start.day + 1, start.hour, start.minute);
      final List<AccountingEntry> entries = all
          .where((AccountingEntry e) =>
              !e.firstUsedAt.isBefore(start) &&
              e.firstUsedAt.isBefore(end) &&
              e.firstUsedAt.isBefore(visibleEnd))
          .toList();
      days.add(_AccountingDay(
          start, entries, accounting.overridesFor(routerKey, start)));
    }
    final double money =
        days.fold<double>(0, (double sum, _AccountingDay d) => sum + d.money);
    final double hours =
        days.fold<double>(0, (double sum, _AccountingDay d) => sum + d.hours);
    final int users =
        days.fold<int>(0, (int sum, _AccountingDay d) => sum + d.users);
    final String timeText =
        '${(settings.startMinute ~/ 60).toString().padLeft(2, '0')}:'
        '${(settings.startMinute % 60).toString().padLeft(2, '0')}';

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(children: <Widget>[
            const Expanded(
                child: Text('Contabilidad',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'Precios y horario',
              onPressed: () => _editSettings(routerKey, settings),
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          Text(
              'Día contable desde las $timeText · '
              'Default ${_money(settings.defaultRate)}/h · '
              'Premium ${_money(settings.premiumRate)}/h',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(color: AppTheme.primary),
          if (accounting.loadError != null)
            Text(accounting.loadError!,
                style: const TextStyle(color: AppTheme.error)),
          if (_trackerInstalled == false) _trackerBanner(),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: <Widget>[
              _rangeChip(1, '24 horas'),
              _rangeChip(2, '48 horas'),
              _rangeChip(3, '72 horas'),
              _rangeChip(7, '1 semana'),
              _rangeChip(30, '1 mes (30 días)'),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            IconButton(
              tooltip: 'Período anterior',
              onPressed: () => setState(() => _periodOffset += _days),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${DateFormat('dd/MM HH:mm').format(first)} – '
                '${DateFormat('dd/MM HH:mm').format(visibleEnd)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Período siguiente',
              onPressed: _periodOffset == 0
                  ? null
                  : () => setState(() => _periodOffset -= _days),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(child: _metric('Dinero', _money(money), Icons.payments)),
            const SizedBox(width: 8),
            Expanded(child: _metric('Usuarios', '$users', Icons.people)),
            const SizedBox(width: 8),
            Expanded(child: _metric('Horas', _hours(hours), Icons.schedule)),
          ]),
          const SizedBox(height: 20),
          const Text('Registro por día',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...days.reversed.map((day) => _dayCard(routerKey, day)),
          const SizedBox(height: 20),
          const Text(
            'Cada usuario se registra al primer uso marcado en MikroTik. '
            'Los precios y horas se guardan con cada registro; los cambios de tarifa '
            'se aplican a los usuarios nuevos. Los ajustes manuales de un día '
            'se indican por separado.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _trackerBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warning.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Activa el registro de primer uso',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                  'MikroTik guardará la fecha aun con la app cerrada. '
                  'Los usuarios anteriores no se incluirán como ventas nuevas.',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              TextButton(
                onPressed: _busy ? null : _activateTracker,
                child: const Text('Activar'),
              ),
            ]),
      );

  Widget _rangeChip(int days, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _days == days,
          onSelected: (_) => setState(() {
            _days = days;
            _periodOffset = 0;
          }),
        ),
      );

  Widget _metric(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(children: <Widget>[
          Icon(icon, color: AppTheme.primary, size: 20),
          const SizedBox(height: 5),
          FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold))),
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ]),
      );

  Widget _dayCard(String router, _AccountingDay day) {
    final bool adjusted = day.overrides.money != null ||
        day.overrides.users != null ||
        day.overrides.hours != null;
    return Card(
      child: ExpansionTile(
        title: Text(DateFormat('dd/MM/yyyy').format(day.start)),
        subtitle: Text(
            '${_money(day.money)} · ${day.users} usuarios · '
            '${_hours(day.hours)} horas${adjusted ? ' · ajustado' : ''}',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        trailing: IconButton(
          tooltip: 'Corregir totales',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => _editDay(router, day),
        ),
        children: <Widget>[
          if (day.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin primeros usos registrados'),
            ),
          ...day.entries.map((AccountingEntry entry) => ListTile(
                dense: true,
                title: Text(entry.userName),
                subtitle: Text('${entry.profile} · '
                    '${DateFormat('HH:mm').format(entry.firstUsedAt)} · '
                    '${_hours(entry.hours)} h × ${_money(entry.hourlyRate)}/h'),
                trailing: Text(_money(entry.amount)),
                onTap: () => _editEntry(entry),
              )),
        ],
      ),
    );
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';
  String _hours(double value) => value.toStringAsFixed(2);
}

class _AccountingDay {
  final DateTime start;
  final List<AccountingEntry> entries;
  final AccountingOverrides overrides;

  const _AccountingDay(this.start, this.entries, this.overrides);

  double get money =>
      overrides.money ??
      entries.fold<double>(
          0, (double sum, AccountingEntry e) => sum + e.amount);
  int get users => overrides.users ?? entries.length;
  double get hours =>
      overrides.hours ??
      entries.fold<double>(0, (double sum, AccountingEntry e) => sum + e.hours);
}
