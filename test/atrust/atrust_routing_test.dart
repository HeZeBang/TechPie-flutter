import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/atrust_routing.dart';

/// The one decision that keeps the tunnel from becoming a foot-gun: it only ever
/// carries the campus, and only while it is armed.
void main() {
  tearDown(() {
    AtrustRouting.enabled = false;
    AtrustRouting.socksProxy = '127.0.0.1:1080';
  });

  test('campus hosts go through the tunnel only while it is armed', () {
    expect(AtrustRouting.forUri(Uri.parse('https://egate.shanghaitech.edu.cn/')), 'DIRECT');

    AtrustRouting.enabled = true;
    expect(
      AtrustRouting.forUri(Uri.parse('https://egate.shanghaitech.edu.cn/')),
      'SOCKS5 127.0.0.1:1080',
    );
    expect(
      AtrustRouting.forUri(Uri.parse('https://ids.shanghaitech.edu.cn/authserver/login')),
      'SOCKS5 127.0.0.1:1080',
    );
  });

  test('nothing outside the campus is ever routed', () {
    AtrustRouting.enabled = true;

    // The tunnel's policy is the controller's: it carries campus destinations
    // and would simply drop the rest.
    for (final host in const [
      'example.com',
      'techpie.geekpie.club',
      'shanghaitech.edu.cn.evil.test',
      'notshanghaitech.edu.cn',
    ]) {
      expect(AtrustRouting.forUri(Uri.parse('https://$host/')), 'DIRECT',
          reason: host,);
    }

    // The bare domain is the campus's own, though.
    expect(
      AtrustRouting.forUri(Uri.parse('https://shanghaitech.edu.cn/')),
      'SOCKS5 127.0.0.1:1080',
    );
  });

  test('an unset proxy address falls back to direct', () {
    AtrustRouting.enabled = true;
    AtrustRouting.socksProxy = '';

    expect(
      AtrustRouting.forUri(Uri.parse('https://egate.shanghaitech.edu.cn/')),
      'DIRECT',
    );
  });

  group('the system-VPN route arithmetic', () {
    test('a gateway is cut out of the range that covers it', () {
      final routes = AtrustRouting.withoutGateways(
        const ['10.0.0.0/8', '119.78.0.0/16', '59.78.0.0/16'],
        const ['10.13.90.147:441', '119.78.254.241:441'],
      );

      // The gateways themselves must stay outside the interface: routing them in
      // is what makes the engine refuse its own dial.
      expect(covers(routes, '10.13.90.147'), isFalse);
      expect(covers(routes, '119.78.254.241'), isFalse);

      // Everything around them is still routed.
      for (final kept in const [
        '10.0.0.1',
        '10.13.90.146',
        '10.13.90.148',
        '10.255.255.255',
        '119.78.254.240',
        '119.78.254.242',
        '59.78.1.2',
      ]) {
        expect(covers(routes, kept), isTrue, reason: kept);
      }

      // And nothing outside the ranges was invented.
      for (final outside in const ['9.255.255.255', '11.0.0.1', '119.79.0.1']) {
        expect(covers(routes, outside), isFalse, reason: outside);
      }
    });

    test('excluding one address from a /8 costs at most 24 entries', () {
      final routes = AtrustRouting.withoutGateways(
        const ['10.0.0.0/8'],
        const ['10.13.90.147:441'],
      );

      // One sibling per level of the path from the /8 down to the /32.
      expect(routes.length, 24);
      expect(covers(routes, '10.13.90.147'), isFalse);
      expect(routes, AtrustRouting.withoutGateways(const ['10.0.0.0/8'], const ['10.13.90.147:441']));
    });

    test('no gateway means the ranges are handed over untouched', () {
      const ranges = ['10.0.0.0/8', '119.78.0.0/16', '59.78.0.0/16'];
      expect(AtrustRouting.withoutGateways(ranges, const []), ranges);
    });

    test('an IPv6 gateway excludes nothing', () {
      // The interface carries IPv4 only, so a `[v6]:port` gateway is not an
      // address this route list could leave out — and must not empty the list.
      expect(
        AtrustRouting.withoutGateways(
          const ['10.0.0.0/8'],
          const ['[2001:da8:801d::1]:441'],
        ),
        const ['10.0.0.0/8'],
      );
    });

    test('a prefix that is not a prefix is passed on, not dropped', () {
      // Silence would be worse than a route the platform refuses by itself.
      final routes = AtrustRouting.withoutGateways(
        const ['10.0.0.0/8', 'vpn.example.com'],
        const ['10.1.1.1'],
      );
      expect(routes, contains('vpn.example.com'));
    });
  });
    test('matches the shared vectors used by the OHOS shell', () {
      final vectors = jsonDecode(
        File('test/atrust/route_vectors.json').readAsStringSync(),
      ) as List;
      for (final vector in vectors) {
        final entry = vector as Map<String, dynamic>;
        expect(
          AtrustRouting.withoutGateways(
            (entry['prefixes'] as List).cast<String>(),
            (entry['gateways'] as List).cast<String>(),
          ),
          (entry['expected'] as List).cast<String>(),
          reason: entry['name'] as String,
        );
      }
    });
}

/// Whether [prefixes] cover [address]. Spelled out again here on purpose: the
/// test must not ask the implementation whether the implementation is right.
bool covers(List<String> prefixes, String address) {
  final target = addressValue(address);
  for (final prefix in prefixes) {
    final slash = prefix.indexOf('/');
    if (slash < 0) continue;
    final base = addressValue(prefix.substring(0, slash));
    final length = int.parse(prefix.substring(slash + 1));
    final mask = length == 0 ? 0 : (0xFFFFFFFF << (32 - length)) & 0xFFFFFFFF;
    if ((target & mask) == (base & mask)) return true;
  }
  return false;
}

int addressValue(String text) {
  var value = 0;
  for (final part in text.split('.')) {
    value = (value << 8) | int.parse(part);
  }
  return value & 0xFFFFFFFF;
}
