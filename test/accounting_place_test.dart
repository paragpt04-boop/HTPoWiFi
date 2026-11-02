import 'package:flutter_test/flutter_test.dart';
import 'package:htpowifi/models/accounting_place.dart';

void main() {
  test('agrupa los doce prefijos con exactamente seis dígitos', () {
    const Map<String, AccountingPlace> cards = <String, AccountingPlace>{
      'wifip123456': AccountingPlace.pasopata,
      'wifiP123456': AccountingPlace.pasopata,
      'wifiP2123456': AccountingPlace.pasopata,
      'premiumP123456': AccountingPlace.pasopata,
      'wifiB123456': AccountingPlace.posoblanco,
      'wifiB2123456': AccountingPlace.posoblanco,
      'premiumB123456': AccountingPlace.posoblanco,
      'wifiL123456': AccountingPlace.lora,
      'wifiL2123456': AccountingPlace.lora,
      'premiumL123456': AccountingPlace.lora,
      'wifiC123456': AccountingPlace.canal,
      'wifiC2123456': AccountingPlace.canal,
      'premiumC123456': AccountingPlace.canal,
    };
    for (final MapEntry<String, AccountingPlace> card in cards.entries) {
      expect(placeForCard(card.key), card.value, reason: card.key);
    }
  });

  test('deja fuera prefijos y longitudes no descritos', () {
    for (final String card in <String>[
      'wifiC12345',
      'wifiC1234567',
      'wifiC21234',
      'wifiC21234567',
      'premiumC2123456',
      'otro123456',
      'xwifiC123456',
    ]) {
      expect(placeForCard(card), AccountingPlace.unclassified, reason: card);
    }
  });
}
