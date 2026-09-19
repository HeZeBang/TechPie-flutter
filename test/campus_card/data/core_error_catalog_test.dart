import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/core/errors/core_error_catalog.dart';
import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads complete localized CORE error catalogs', () async {
    await CoreErrorCatalog.initialize();

    expect(CoreErrorCatalog.message('CORE20003', languageCode: 'zh'), '密码错误');
    expect(
      CoreErrorCatalog.message('CORE20003', languageCode: 'en'),
      'Password Error',
    );
    expect(
      CoreErrorCatalog.message('CORE20137', languageCode: 'zh'),
      '卡参数修改成功',
    );
    expect(CoreErrorCatalog.message('NOT-A-CORE-CODE'), isNull);
    expect(requireObjectMap('CORE10008', context: 'SYNTHETIC'), {
      'success': true,
      'message': 'CORE10008',
    });
    expect(
      () => requireObjectMap('CORE20003', context: 'SYNTHETIC'),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.safeMessage,
          'safeMessage',
          anyOf('密码错误', 'Password Error'),
        ),
      ),
    );
  });
}
