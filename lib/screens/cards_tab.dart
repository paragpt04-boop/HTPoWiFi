import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/hotspot_user.dart';
import '../providers/router_provider.dart';
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

    setState(() => _generating = true);

    final api = context.read<RouterProvider>().api;
    if (api == null) return;

    final cards = <_CardData>[];
    final rng = Random();
    int created = 0;

    for (int i = 0; i < qty; i++) {
      final code = rng.nextInt(900000) + 100000;
      final name = '${_prefix}$code';
      final pass = '${rng.nextInt(9000) + 1000}';

      final user = HotspotUser(
        name: name,
        password: pass,
        server: 'hotspot-nauta',
        limitUptime: _selectedTime,
      );

      final ok = await api.addUser(user);
      if (ok) {
        cards.add(_CardData(name: name, password: pass, time: _selectedTime));
        created++;
      }
    }

    setState(() {
      _generated = cards;
      _generating = false;
    });

    _showSnack('$created tarjetas creadas');
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
      duration: const Duration(seconds: 2),
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
