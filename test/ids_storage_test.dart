import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/utils/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Map<String, dynamic> legacyAccount(String platform) => {
        'platform': platform,
        'account': '20240001',
        'token': 'synthetic-token',
        'autoRenew': true,
        'password': 'synthetic-password',
        'boundAt': '2026-01-01T00:00:00.000Z',
      };

  for (final alias in ['cpdaily', 'egate']) {
    test('published $alias storage becomes an IDS account with upgrade credentials', () async {
      final oldKey = 'third_party_$alias';
      await appSecureStorage.write(key: oldKey, value: jsonEncode(legacyAccount(alias)));
      final storage = StorageService(await SharedPreferences.getInstance());

      final account = (await storage.loadAllThirdPartyAccounts()).single;
      expect(account.platform, ThirdPartyPlatform.ids);
      expect(account.account, '20240001');
      expect(account.password, 'synthetic-password');
      final canonical = jsonDecode((await appSecureStorage.read(key: 'third_party_ids'))!)
          as Map<String, dynamic>;
      expect(canonical['platform'], 'ids');
      expect(await appSecureStorage.read(key: oldKey), isNull);

      await storage.clearThirdPartyAccount(ThirdPartyPlatform.ids);
      expect(await storage.loadAllThirdPartyAccounts(), isEmpty);
    });
  }

  test('removing IDS also removes stale aliases so they cannot reappear after restart', () async {
    final storage = StorageService(await SharedPreferences.getInstance());
    await appSecureStorage.write(key: 'third_party_ids', value: jsonEncode(legacyAccount('ids')));
    for (final alias in ['cpdaily', 'egate']) {
      await appSecureStorage.write(
        key: 'third_party_$alias',
        value: jsonEncode(legacyAccount(alias)),
      );
    }
    expect((await storage.loadAllThirdPartyAccounts()).single.platform, ThirdPartyPlatform.ids);

    await storage.clearThirdPartyAccount(ThirdPartyPlatform.ids);
    final restarted = StorageService(await SharedPreferences.getInstance());
    expect(await restarted.loadAllThirdPartyAccounts(), isEmpty);
  });
}
