import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/wearable_device.dart';
import 'package:techpie/services/storage_service.dart';

void main() {
  test('longer model names do not expose controls for a different device', () {
    final base = wearableBandCatalog.firstWhere((d) => d.id == 'band9');
    final pro = wearableBandCatalog.firstWhere((d) => d.id == 'band9-pro');
    expect(matchesConnectedNode(base, 'Xiaomi 手环9 Pro'), isFalse);
    expect(matchesConnectedNode(pro, 'Xiaomi 手环9 Pro'), isTrue);
    expect(matchesConnectedNode(base, null), isFalse);
  });

  test('new installs have no synthetic device and duplicate models persist', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    expect(storage.storedWearableDevices, isNull);
    final band = wearableBandCatalog.first;
    await storage.setWearableDevices([band, band]);
    expect(storage.storedWearableDevices!.map((d) => d.id), [band.id, band.id]);
    await storage.setWearableDevices([band]);
    expect(storage.storedWearableDevices, hasLength(1));
    await storage.setWearableDevices([]);
    expect(storage.storedWearableDevices, isEmpty);
  });
}
