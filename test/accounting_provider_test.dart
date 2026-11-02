import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:htpowifi/models/accounting_entry.dart';
import 'package:htpowifi/models/hotspot_user.dart';
import 'package:htpowifi/models/router_config.dart';
import 'package:htpowifi/providers/accounting_provider.dart';

void main() {
  final RouterConfig config =
      RouterConfig(host: '192.168.88.1', username: 'admin', password: 'secret');

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('solo registra primer uso fechado y no duplica al volver a leer',
      () async {
    final AccountingProvider accounting = AccountingProvider();
    final HotspotUser old = HotspotUser(
      id: '*1',
      name: 'anterior',
      profile: 'default',
      limitUptime: '1h',
      uptime: '1h',
      comment: '[ACC:?]',
      password: 'x',
    );
    final HotspotUser premium = HotspotUser(
      id: '*2',
      name: 'tarjeta',
      profile: 'Premium',
      limitUptime: '2h',
      uptime: '1m',
      comment: '[ACC:2026-10-18 07:01:00]',
      password: 'x',
    );

    expect(
        await accounting.observeUsers(config, <HotspotUser>[old, premium]), 1);
    expect(
        await accounting.observeUsers(config, <HotspotUser>[old, premium]), 0);
    final entries = accounting.entriesFor(AccountingProvider.routerKey(config));
    expect(entries.length, 1);
    expect(entries.single.hours, 2);
    expect(entries.single.hourlyRate, 250);
    expect(entries.single.amount, 500);
  });

  test('cambio de tarifa no modifica registros previos', () async {
    final AccountingProvider accounting = AccountingProvider();
    final String router = AccountingProvider.routerKey(config);
    await accounting.observeUsers(config, <HotspotUser>[
      HotspotUser(
          id: '*1',
          name: 'uno',
          password: 'x',
          profile: 'default',
          limitUptime: '1h',
          comment: '[ACC:2026-10-18 07:01:00]'),
    ]);
    await accounting.updateSettings(
        router, const AccountingSettings(defaultRate: 200, premiumRate: 250));
    await accounting.observeUsers(config, <HotspotUser>[
      HotspotUser(
          id: '*2',
          name: 'dos',
          password: 'x',
          profile: 'default',
          limitUptime: '1h',
          comment: '[ACC:2026-10-18 07:02:00]'),
    ]);
    expect(accounting.entriesFor(router).map((e) => e.amount),
        containsAll(<double>[150, 200]));
  });

  test('el cierre diario separa 06:59 de 07:00', () {
    expect(AccountingProvider.dayStart(DateTime(2026, 10, 18, 6, 59), 420),
        DateTime(2026, 10, 17, 7));
    expect(AccountingProvider.dayStart(DateTime(2026, 10, 18, 7), 420),
        DateTime(2026, 10, 18, 7));
    expect(AccountingProvider.rangeStart(DateTime(2026, 10, 18, 8), 420, 3),
        DateTime(2026, 10, 16, 7));
  });

  test('el historial y las correcciones sobreviven al cierre de la app',
      () async {
    final AccountingProvider first = AccountingProvider();
    final String router = AccountingProvider.routerKey(config);
    await first.observeUsers(config, <HotspotUser>[
      HotspotUser(
          id: '*5',
          name: 'cinco',
          password: 'x',
          profile: 'default',
          limitUptime: '1h',
          comment: '[ACC:2026-10-18 08:00:00]'),
    ]);
    final DateTime day = DateTime(2026, 10, 18, 7);
    await first.updateOverrides(
        router, day, const AccountingOverrides(hours: 2, money: 300));

    final AccountingProvider reopened = AccountingProvider();
    await reopened.load();
    expect(reopened.entriesFor(router).single.amount, 150);
    expect(reopened.overridesFor(router, day).hours, 2);
    expect(reopened.overridesFor(router, day).money, 300);
  });

  test('la marca de primer uso no aparece en el comentario visible', () {
    final HotspotUser user = HotspotUser(
      id: '*1',
      name: 'uno',
      password: 'x',
      comment: 'nota [EXP:2026-10-18 09:00:00] [ACC:2026-10-18 07:00:00]',
    );
    expect(user.cleanComment, 'nota');
    expect(user.commentWithTag('2026-10-19 09:00:00'),
        contains('[ACC:2026-10-18 07:00:00]'));
    expect(
        user.commentWithFirstTag('?'), contains('[EXP:2026-10-18 09:00:00]'));
  });
}
