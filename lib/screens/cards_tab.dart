import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/hotspot_user.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';

class CardsTab extends StatefulWidget {
  const CardsTab({super.key});

  @override
  State<CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends State<CardsTab> {
  final _quantityCtl = TextEditingController(text: '10');
  String _selectedTime = '1h';
  String _prefix = 'wifi';
  bool _generating = false;
  List<_CardData> _generated = [];

  final _times = {
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

  Future<void> _generate() async {
    final qty = int.tryParse(_quantityCtl.text) ?? 0;
    if (qty <= 0 || qty > 100) {
      _showSnack('Cantidad entre 1 y 100', isError: true);
      return;
    }

    final prov = context.read<RouterProvider>();
    final api = prov.api;
    if (api == null) {
      _showSnack('Sin conexion al router', isError: true);
      return;
    }

    setState(() => _generating = true);

    final cards = <_CardData>[];
    final rng = Random();
    String? firstError;

    // Nombres ya existentes en el router: evita colisiones silenciosas.
    Set<String> taken;
    try {
      taken = await api.getUserNames();
    } on MikroTikException catch (e) {
      if (mounted) setState(() => _generating = false);
      _showSnack(e.message, isError: true);
      return;
    }

    for (int i = 0; i < qty; i++) {
      String name = '';
      for (int attempt = 0; attempt < 50; attempt++) {
        final candidate = '$_prefix${rng.nextInt(900000) + 100000}';
        if (!taken.contains(candidate)) {
          name = candidate;
          break;
        }
      }
      if (name.isEmpty) {
        firstError ??= 'No se pudieron generar nombres unicos.';
        break;
      }
      taken.add(name);

      final pass = '${rng.nextInt(9000) + 1000}';
      final user = HotspotUser(
        name: name,
        password: pass,
        server: prov.selectedServer,
        profile: prov.selectedProfile,
        limitUptime: _selectedTime,
      );

      try {
        await api.addUser(user);
        cards.add(_CardData(name: name, password: pass, time: _selectedTime));
      } on MikroTikException catch (e) {
        firstError ??= e.message;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _generated = cards;
      _generating = false;
    });

    if (firstError != null) {
      _showSnack('Creadas ${cards.length} de $qty. $firstError', isError: true);
    } else {
      _showSnack('${cards.length} tarjetas creadas');
    }
  }

  void _copyAll() {
    if (_generated.isEmpty) return;
    final text = _generated
        .map((c) => 'Usuario: ${c.name}  |  Clave: ${c.password}  |  Tiempo: ${c.time}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Copiado al portapapeles');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      duration: Duration(seconds: isError ? 6 : 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Generator card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.card_membership,
                      color: AppTheme.primary, size: 20),
                  SizedBox(width: 8),
                  Text('Generar Tarjetas',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              // Prefix
              TextField(
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Prefijo del usuario',
                  hintText: 'wifi',
                  prefixIcon:
                      Icon(Icons.label, color: AppTheme.textSecondary),
                ),
                onChanged: (v) => _prefix = v.trim().isEmpty ? 'wifi' : v.trim(),
              ),
              const SizedBox(height: 12),
              // Quantity & Time
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityCtl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        prefixIcon: Icon(Icons.numbers,
                            color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedTime,
                      dropdownColor: AppTheme.cardLight,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Tiempo',
                        prefixIcon: Icon(Icons.timer,
                            color: AppTheme.textSecondary),
                      ),
                      items: _times.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedTime = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Servidor + Perfil (leidos del router)
              Consumer<RouterProvider>(
                builder: (ctx, prov, _) => Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: prov.servers.contains(prov.selectedServer)
                            ? prov.selectedServer
                            : prov.servers.first,
                        dropdownColor: AppTheme.cardLight,
                        isExpanded: true,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Servidor',
                          prefixIcon:
                              Icon(Icons.dns, color: AppTheme.textSecondary),
                        ),
                        items: prov.servers
                            .map((sv) => DropdownMenuItem(
                                value: sv,
                                child: Text(sv,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) prov.setServer(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: prov.profiles.contains(prov.selectedProfile)
                            ? prov.selectedProfile
                            : prov.profiles.first,
                        dropdownColor: AppTheme.cardLight,
                        isExpanded: true,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Perfil',
                          prefixIcon:
                              Icon(Icons.speed, color: AppTheme.textSecondary),
                        ),
                        items: prov.profiles
                            .map((pf) => DropdownMenuItem(
                                value: pf,
                                child: Text(pf,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) prov.setProfile(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Generate button
              ElevatedButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.auto_awesome),
                label: Text(
                    _generating ? 'Generando...' : 'Generar Tarjetas'),
              ),
            ],
          ),
        ),

        // Results
        if (_generated.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text('${_generated.length} tarjetas generadas',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyAll,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar todo', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(
            _generated.length,
            (i) => _CardTile(card: _generated[i], index: i + 1),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _quantityCtl.dispose();
    super.dispose();
  }
}

class _CardData {
  final String name;
  final String password;
  final String time;
  _CardData({required this.name, required this.password, required this.time});
}

class _CardTile extends StatelessWidget {
  final _CardData card;
  final int index;

  const _CardTile({required this.card, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text('$index',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 14)),
                Text('Clave: ${card.password}  •  ${card.time}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: AppTheme.textSecondary, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: 'Usuario: ${card.name}  Clave: ${card.password}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copiado'),
                duration: Duration(seconds: 1),
                backgroundColor: AppTheme.success,
              ));
            },
          ),
        ],
      ),
    );
  }
}
