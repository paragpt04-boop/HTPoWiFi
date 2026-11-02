enum AccountingPlace { all, pasopata, posoblanco, lora, canal, unclassified }

extension AccountingPlaceLabel on AccountingPlace {
  String get label {
    switch (this) {
      case AccountingPlace.all:
        return 'Todos';
      case AccountingPlace.pasopata:
        return 'Pasopata';
      case AccountingPlace.posoblanco:
        return 'Posoblanco';
      case AccountingPlace.lora:
        return 'Lora';
      case AccountingPlace.canal:
        return 'El Canal';
      case AccountingPlace.unclassified:
        return 'Sin clasificar';
    }
  }
}

/// Reconoce solo las tarjetas descritas: prefijo, posible 2 y seis dígitos.
AccountingPlace placeForCard(String name) {
  final String card = name.toLowerCase();
  const Map<String, AccountingPlace> suffixes = <String, AccountingPlace>{
    'p': AccountingPlace.pasopata,
    'b': AccountingPlace.posoblanco,
    'l': AccountingPlace.lora,
    'c': AccountingPlace.canal,
  };
  final RegExpMatch? match =
      RegExp(r'^(?:wifi|premium)([pblc])(2)?[0-9]{6}$').firstMatch(card);
  if (match == null) return AccountingPlace.unclassified;
  // Las Premium indicadas no llevan el 2 de las tarjetas wifi de dos horas.
  if (card.startsWith('premium') && match.group(2) != null) {
    return AccountingPlace.unclassified;
  }
  return suffixes[match.group(1)]!;
}
