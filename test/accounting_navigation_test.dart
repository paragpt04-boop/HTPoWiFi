import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:htpowifi/models/router_config.dart' as app;
import 'package:htpowifi/providers/accounting_provider.dart';
import 'package:htpowifi/providers/auth_provider.dart';
import 'package:htpowifi/providers/router_provider.dart';
import 'package:htpowifi/screens/home_screen.dart';
import 'package:htpowifi/utils/app_theme.dart';

class _OfflineRouterProvider extends RouterProvider {
  final app.RouterConfig _testConfig = app.RouterConfig(
      host: '192.168.88.1', username: 'admin', password: 'secret');

  @override
  app.RouterConfig? get config => _testConfig;
}

void main() {
  testWidgets('la pestaña Contabilidad abre en una pantalla de teléfono',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<RouterProvider>(
            create: (_) => _OfflineRouterProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<AccountingProvider>(
            create: (_) => AccountingProvider()),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder navigation = find.byType(BottomNavigationBar);
    await tester.tap(
        find.descendant(of: navigation, matching: find.text('Contabilidad')));
    await tester.pumpAndSettle();

    expect(find.text('24 horas'), findsOneWidget);
    expect(find.text('48 horas'), findsOneWidget);
    expect(find.text('Usuarios'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
