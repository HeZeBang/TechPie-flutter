/// 用户在「穿戴设备」页自行添加的设备条目。
class WearableDevice {
  const WearableDevice({required this.id, required this.name});

  final String id;
  final String name;

  bool get isAppleWatch => id == 'apple-watch';
  bool get isBand => id.startsWith('band');

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static WearableDevice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String) return null;
    return WearableDevice(id: id, name: name);
  }
}

const appleWatchDevice = WearableDevice(id: 'apple-watch', name: 'Apple Watch');

/// 节点名（如「小米手环9 NFC版」）与目录名归一化后做包含匹配，
/// 且只让最长命中的目录名匹配，避免一个节点被多个条目认领。
bool matchesConnectedNode(WearableDevice device, String? nodeName) {
  if (nodeName == null || nodeName.isEmpty) return false;
  String norm(String s) => s
      .toLowerCase()
      .replaceAll('xiaomi', '小米')
      .replaceAll(RegExp(r'\s|小米'), '');
  final node = norm(nodeName);
  final self = norm(device.name);
  if (!node.contains(self)) return false;
  for (final other in wearableBandCatalog) {
    final otherName = norm(other.name);
    if (otherName.length > self.length && node.contains(otherName)) {
      return false;
    }
  }
  return true;
}

/// 可配置的设备名称；连接和消息投递仍取决于厂商服务与设备固件。
const wearableBandCatalog = <WearableDevice>[
  WearableDevice(id: 'band8-pro', name: '小米手环8 Pro'),
  WearableDevice(id: 'band9', name: '小米手环9'),
  WearableDevice(id: 'band9-pro', name: '小米手环9 Pro'),
  WearableDevice(id: 'band10', name: '小米手环10'),
  WearableDevice(id: 'band10-pro', name: '小米手环10 Pro'),
  WearableDevice(id: 'band11', name: '小米手环11'),
  WearableDevice(id: 'watch-s3', name: '小米Watch S3'),
  WearableDevice(id: 'watch-s4', name: '小米Watch S4'),
  WearableDevice(id: 'watch-s4-41', name: '小米Watch S4 41mm'),
  WearableDevice(id: 'watch-s5', name: '小米Watch S5'),
  WearableDevice(id: 'watch-5', name: '小米Watch 5'),
];
