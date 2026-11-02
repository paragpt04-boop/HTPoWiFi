class AccountingEntry {
  final String id;
  final String routerKey;
  final String userName;
  final String profile;
  final DateTime firstUsedAt;
  final double hours;
  final double hourlyRate;

  const AccountingEntry({
    required this.id,
    required this.routerKey,
    required this.userName,
    required this.profile,
    required this.firstUsedAt,
    required this.hours,
    required this.hourlyRate,
  });

  double get amount => hours * hourlyRate;

  AccountingEntry copyWith({double? hours, double? hourlyRate}) =>
      AccountingEntry(
        id: id,
        routerKey: routerKey,
        userName: userName,
        profile: profile,
        firstUsedAt: firstUsedAt,
        hours: hours ?? this.hours,
        hourlyRate: hourlyRate ?? this.hourlyRate,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'routerKey': routerKey,
        'userName': userName,
        'profile': profile,
        'firstUsedAt': firstUsedAt.toIso8601String(),
        'hours': hours,
        'hourlyRate': hourlyRate,
      };

  factory AccountingEntry.fromJson(Map<String, dynamic> json) =>
      AccountingEntry(
        id: json['id'] as String,
        routerKey: json['routerKey'] as String,
        userName: json['userName'] as String,
        profile: json['profile'] as String,
        firstUsedAt: DateTime.parse(json['firstUsedAt'] as String),
        hours: (json['hours'] as num).toDouble(),
        hourlyRate: (json['hourlyRate'] as num).toDouble(),
      );
}

class AccountingSettings {
  final double defaultRate;
  final double premiumRate;
  final int startMinute;

  const AccountingSettings({
    this.defaultRate = 150,
    this.premiumRate = 250,
    this.startMinute = 7 * 60,
  });

  double rateFor(String profile) {
    switch (profile.toLowerCase()) {
      case 'default':
        return defaultRate;
      case 'premium':
        return premiumRate;
      default:
        return 0;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'defaultRate': defaultRate,
        'premiumRate': premiumRate,
        'startMinute': startMinute,
      };

  factory AccountingSettings.fromJson(Map<String, dynamic> json) =>
      AccountingSettings(
        defaultRate: (json['defaultRate'] as num?)?.toDouble() ?? 150,
        premiumRate: (json['premiumRate'] as num?)?.toDouble() ?? 250,
        startMinute: (json['startMinute'] as num?)?.toInt() ?? 7 * 60,
      );
}

class AccountingOverrides {
  final double? money;
  final int? users;
  final double? hours;

  const AccountingOverrides({this.money, this.users, this.hours});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'money': money,
        'users': users,
        'hours': hours,
      };

  factory AccountingOverrides.fromJson(Map<String, dynamic> json) =>
      AccountingOverrides(
        money: (json['money'] as num?)?.toDouble(),
        users: (json['users'] as num?)?.toInt(),
        hours: (json['hours'] as num?)?.toDouble(),
      );
}
