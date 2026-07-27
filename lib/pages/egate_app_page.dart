import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/egate_app_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import 'login_page.dart';
import 'third_party_accounts_page.dart';

/// "校园签到" — queries the egate-app (xshdapp) sign-in announcement +
/// history and lets the user submit a check-in for a scanned WID. Session
/// cookies are derived from the cpdaily binding (see EgateAppService), so
/// this page mirrors OaGymPage's ready/unready gating.
class EgateAppPage extends StatefulWidget {
  const EgateAppPage({super.key});

  @override
  State<EgateAppPage> createState() => _EgateAppPageState();
}

class _EgateAppPageState extends State<EgateAppPage> {
  bool _loading = false;
  String? _error;
  String? _message;
  List<EgateAppSignRecord> _history = const [];
  bool _loadedOnce = false;

  Future<void> _handleLogin() async {
    final sp = ServiceProvider.of(context);
    final alreadyLoggedIn = sp.authService.isLoggedIn;
    await presentLoginPage(context);
    if (!mounted) return;
    if (alreadyLoggedIn && sp.authService.isLoggedIn) {
      unawaited(_openThirdPartyAccounts());
    }
    setState(() {});
  }

  Future<void> _openThirdPartyAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ThirdPartyAccountsPage()),
    );
  }

  Future<void> _refresh(EgateAppService service) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        service.fetchSignMessage(),
        service.fetchSignHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        _message = results[0] as String;
        _history = results[1] as List<EgateAppSignRecord>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitCheckin(EgateAppService service, String wid) async {
    try {
      final result = await service.submitCheckin(wid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      unawaited(_refresh(service));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _scanQrCode(EgateAppService service) async {
    final wid = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _QrScanPage()),
    );
    if (wid == null || wid.isEmpty || !mounted) return;
    unawaited(_submitCheckin(service, wid));
  }

  Future<void> _enterWidManually(EgateAppService service) async {
    final controller = TextEditingController();
    final wid = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动输入签到内容'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '粘贴或输入二维码内容 (WID)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (wid == null || wid.isEmpty || !mounted) return;
    unawaited(_submitCheckin(service, wid));
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final tpAuth = sp.thirdPartyAuthService;
    final service = sp.egateAppService;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;
    final canScanWithCamera = isAndroid() || isIos();

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '校园签到',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Home',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Home',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (id) {
                switch (id) {
                  case 'back':
                    unawaited(Navigator.maybePop(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('校园签到')),
      body: ListenableBuilder(
        listenable: Listenable.merge([auth, tpAuth]),
        builder: (context, _) {
          final ready = auth.isLoggedIn && tpAuth.hasCpdailyBinding;
          if (!ready) {
            return ListView(
              padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 120),
              children: [
                Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.login_rounded,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          auth.isLoggedIn ? '需要绑定 eGate 账号' : '需要先登录 TechPie',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          auth.isLoggedIn
                              ? '校园签到复用 eGate 绑定的校园网登录态，请在「第三方账号」中绑定 eGate 后再使用。'
                              : '校园签到复用 eGate 绑定的校园网登录态，不需要单独保存密码。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _handleLogin,
                          icon: const Icon(Icons.login),
                          label: Text(auth.isLoggedIn ? '去绑定 eGate' : '去登录'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          if (!_loadedOnce) {
            _loadedOnce = true;
            // Defer past this build: _refresh() calls setState() before its
            // first await, and this branch runs synchronously inside
            // EgateAppPage's own build() (via ListenableBuilder), so calling
            // it directly here would re-enter the build that's still in
            // progress.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_refresh(service));
            });
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(service),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 120),
              children: [
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!),
                    ),
                  ),
                Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('当前公告', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          _loading
                              ? '加载中…'
                              : (_message?.isNotEmpty == true ? _message! : '暂无签到公告'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (canScanWithCamera)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => unawaited(_scanQrCode(service)),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('扫码签到'),
                        ),
                      ),
                    if (canScanWithCamera) const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => unawaited(_enterWidManually(service)),
                        icon: const Icon(Icons.keyboard),
                        label: const Text('手动输入'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('签到历史', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_history.isEmpty && !_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('暂无签到记录')),
                  ),
                for (final record in _history)
                  Card(
                    child: ListTile(
                      title: Text(record.activityName),
                      subtitle: Text(
                        [
                          record.typeDisplay,
                          if (record.date != null) record.date!,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Text(record.statusDisplay),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen camera QR scanner. Pops with the raw decoded string (the WID
/// content) as soon as one barcode is found — no decryption/transformation,
/// the scanned text is submitted to the backend verbatim.
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描签到二维码')),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
