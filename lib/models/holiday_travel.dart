class HolidayTravel {
  HolidayTravel(Map<String, dynamic> row)
      : fields = {
          for (final key in keys)
            if ((row[key] is String || row[key] is num) && row[key].toString().trim().isNotEmpty)
              key: row[key].toString().trim(),
        };
  static const keys = {
    'WID',
    'DJWID',
    'DJRQ',
    'DJXN',
    'JJRDM',
    'JJRDM_DISPLAY',
    'QRZT',
    'QRZT_DISPLAY',
    'LXRQ',
    'YJFXRQ',
    'LXYYDM',
    'LXYYDM_DISPLAY',
    'YL8',
    'YL8_DISPLAY',
    'YL5',
    'YL6',
    'YL7',
    'YL4',
    'YL5_DISPLAY',
    'YL6_DISPLAY',
    'YL7_DISPLAY',
    'QXSF_DISPLAY',
    'QXCS_DISPLAY',
    'QXQX_DISPLAY',
    'QXSF',
    'QXCS',
    'QXQX',
    'QXDZ',
    'JJLXRDH',
  };
  final Map<String, String> fields;
  String operator [](String key) => fields[key] ?? '';
  String get holiday => fields['JJRDM_DISPLAY'] ?? this['JJRDM'];
  String get status => fields['QRZT_DISPLAY'] ?? this['QRZT'];

  /// Copies only destination and emergency contact details. Registration IDs,
  /// dates and the source holiday belong to a different application.
  Map<String, String> destinationDefaults() => {
        'QXSF': fields['QXSF'] ?? this['YL5'],
        'QXCS': fields['QXCS'] ?? this['YL6'],
        'QXQX': fields['QXQX'] ?? this['YL7'],
        'QXDZ': fields['QXDZ'] ?? this['YL4'],
        'JJLXRDH': this['JJLXRDH'],
      };

  String get region => [
        fields['QXSF_DISPLAY'] ?? fields['YL5_DISPLAY'] ?? destinationDefaults()['QXSF'],
        fields['QXCS_DISPLAY'] ?? fields['YL6_DISPLAY'] ?? destinationDefaults()['QXCS'],
        fields['QXQX_DISPLAY'] ?? fields['YL7_DISPLAY'] ?? destinationDefaults()['QXQX'],
      ].whereType<String>().where((v) => v.isNotEmpty).join(' ');

  Map<String, String> get reviewFields => {
        '省市区': region,
        '详细地址': destinationDefaults()['QXDZ']!,
        '紧急联系人电话': this['JJLXRDH'],
      };

  DateTime? get registrationDate =>
      DateTime.tryParse(this['DJRQ']) ?? DateTime.tryParse(this['LXRQ']);

  static bool validDates(DateTime departure, DateTime expectedReturn) =>
      !DateTime(departure.year, departure.month, departure.day)
          .isAfter(DateTime(expectedReturn.year, expectedReturn.month, expectedReturn.day));
}
