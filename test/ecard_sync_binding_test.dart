import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/models/ecard_sync_binding.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/sync_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const openId = 'SYNTHETIC_OPENID_123456';
  EcardSyncBinding binding(String? value, int time) => EcardSyncBinding(openId: value,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true), deviceId: 'test-device',);
  SyncEnvelope envelope(EcardSyncBinding? value) => SyncEnvelope(v: 2, accounts: [], tombstones: [], ecard: value);

  test('eCard round trips independently of existing linked-account platforms', () {
    final value = envelope(binding(openId, 10));
    final decoded = SyncEnvelope.decode(value.encode())!;
    expect(decoded.accounts, isEmpty);
    expect(decoded.ecard!.openId, openId);
    expect(jsonDecode(value.encode())['ecard'].keys.toSet(), {'openid', 'channel', 'updatedAt', 'deviceId'});
  });
  test('legacy channel defaults to WeChat and unknown channels are not accepted', () {
    final old = binding(openId, 10).toJson()..remove('channel');
    expect(EcardSyncBinding.fromJson(old)!.channel, EcardOpenIdChannel.wechat);
    expect(EcardSyncBinding.fromJson({...old, 'channel': 'unknown'}), isNull);
    final ali = EcardSyncBinding(openId: openId, channel: EcardOpenIdChannel.alipay,
      updatedAt: DateTime.utc(2026), deviceId: 'device',);
    expect(SyncEnvelope.decode(envelope(ali).encode())!.ecard!.channel, EcardOpenIdChannel.alipay);
  });
  test('legacy backups do not delete eCard and newer tombstones prevent resurrection', () {
    final local = envelope(binding(openId, 10));
    final legacy = SyncEnvelope.decode('{"v":2,"accounts":[],"tombstones":[]}')!;
    expect(local.mergeWith(legacy).ecard!.openId, openId);
    final deleted = envelope(binding(null, 20));
    expect(local.mergeWith(deleted).ecard!.openId, isNull);
    expect(deleted.mergeWith(local).ecard!.openId, isNull);
    expect(deleted.mergeWith(envelope(binding(openId, 30))).ecard!.openId, openId);
    expect(local.mergeWith(envelope(binding(null, 10))).ecard!.openId, isNull);
  });
  test('restore stages only OPENID, without inventing an authenticated cookie or identity', () async {
    final secure = InMemorySecureCredentialStore();
    final service = CampusCardService.withStore(secure);
    addTearDown(service.dispose);
    final sessions = SecureSessionCredentialStore(secure);
    await service.applySyncBinding(binding(openId, 10));
    expect(await sessions.readOpenId(), openId);
    expect(await sessions.readSessionCookie(), isNull);
    expect(await sessions.readVerifiedIdSerial(), isNull);
    expect(service.configured, isTrue);
    await service.applySyncBinding(EcardSyncBinding(openId: openId, channel: EcardOpenIdChannel.alipay,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(15, isUtc: true), deviceId: 'test-device',),);
    expect(await sessions.readOpenIdChannel(), EcardOpenIdChannel.alipay);
    expect(service.openIdChannel, EcardOpenIdChannel.alipay);
    expect((await service.readSyncBinding())!.channel, EcardOpenIdChannel.alipay);
    await service.applySyncBinding(binding(null, 20));
    expect(await sessions.readOpenId(), isNull);
    await service.applySyncBinding(binding(openId, 10));
    expect(await sessions.readOpenId(), isNull);
    expect((await service.readSyncBinding())!.openId, isNull);
  });
}
