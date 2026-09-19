import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_offline_authorization_remote.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';
import 'package:techpie/features/campus_card/domain/ports/offline_ports.dart';

import '../support/fake_ecard_transport.dart';

void main() {
  test('maps backend zero quota to unlimited authorization', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/offlineCode/openOfflineCode', {
        'success': true,
        'data': {
          'data': {
            'authorinfo': '56380101AABBCCDD',
            'offlineqrcodenum': '0',
            'authordate': '20260909',
          },
        },
      });
    final remote = EcardOfflineAuthorizationRemote(
      client: transport,
      backendSecurityApproval: true,
    );

    final response = await remote.activate(
      OfflineActivationRequest(
        cardId: 'SYNTHETIC-STUDENT',
        deviceCode: 'SYNTHETIC-DEVICE',
        publicKeyCompressed: '02${List.filled(64, 'A').join()}',
        privateKeyHex: List.filled(64, 'B').join(),
      ),
    );

    expect(response.totalUses, isNull);
    expect(response.expiresOn, DateTime.utc(2026, 9, 9));
  });

  test('renewal reads zero quota as unlimited', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/home/getUserkeys', {
        'success': true,
        'data': {
          'ukey': {
            'result': true,
            'authorinfo': '56380101AABBCCDD',
            'offlineqrcodenum': '0',
            'authordate': '20260909',
          },
        },
      });
    final remote = EcardOfflineAuthorizationRemote(
      client: transport,
      backendSecurityApproval: true,
    );

    final response = await remote.renew(
      OfflineAuthorization(
        cardId: 'SYNTHETIC-STUDENT',
        deviceCode: 'SYNTHETIC-DEVICE',
        publicKeyCompressed: '02${List.filled(64, 'A').join()}',
        authorInfo: '56380101EEFF',
        totalUses: 10,
        used: 4,
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );

    expect(response, isNotNull);
    expect(response!.totalUses, isNull);
  });
}
