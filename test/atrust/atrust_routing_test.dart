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
}
