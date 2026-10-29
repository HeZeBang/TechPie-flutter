import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/uni_auth_webview_page.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/utils/platform.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  // These cover the iOS 26 chrome; the pre-26 fallback has its own tests.
  setUp(() => debugUsesIosLiquidGlass = true);
  tearDown(() => debugUsesIosLiquidGlass = false);
  late _Browser browser;
  setUp(() {
    browser = _Browser();
    WebViewPlatform.instance = browser;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS login opens the OAuth WebView directly and native back cancels', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final service = UniAuthService();
    addTearDown(service.dispose);
    Object? error;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                try {
                  await service.login(context);
                } catch (e) {
                  error = e;
                }
              },
              child: const Text('Login'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.byType(UniAuthWebViewPage), findsOneWidget);
    final url = browser.controller.loads.single;
    expect(url.host, 'auth.geekpie.club');
    expect(url.queryParameters['client_id'], isNotEmpty);
    expect(url.queryParameters['redirect_uri'], 'techpie://auth-callback');
    expect(url.queryParameters['code_challenge'], isNotEmpty);
    expect(service.loading, isTrue);
    tester.widgetList<CNButton>(find.byType(CNButton)).single.onPressed!();
    await tester.pumpAndSettle();
    expect(error, isA<CasdoorAuthCancelledException>());
    expect(service.loading, isFalse);
    expect(find.text('Login'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('only the main-frame callback completes once; failures can retry', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => UniAuthWebViewPage(
                      authorizeUrl:
                          'https://auth.geekpie.club/login/oauth/authorize?client_id=test',
                      callbackUri: Uri.parse('techpie://auth-callback'),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final delegate = browser.delegate;
    delegate.error!(
      const WebResourceError(errorCode: -2, description: 'offline', isForMainFrame: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('认证页面加载失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(browser.controller.loads, hasLength(2));
    expect(find.text('认证页面加载失败，请重试'), findsNothing);
    expect(
      await delegate.navigate!(
        const NavigationRequest(url: 'https://auth.geekpie.club/login', isMainFrame: true),
      ),
      NavigationDecision.navigate,
    );
    const subframe = NavigationRequest(
      url: 'techpie://auth-callback?code=subframe',
      isMainFrame: false,
    );
    expect(await delegate.navigate!(subframe), NavigationDecision.prevent);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(UniAuthWebViewPage), findsOneWidget);

    // Our scheme on another host is not the callback: it does not complete,
    // and the page says so instead of sitting on a dead provider page.
    const wrong = NavigationRequest(url: 'techpie://other?code=wrong', isMainFrame: true);
    expect(await delegate.navigate!(wrong), NavigationDecision.prevent);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('认证回调无效，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('认证回调无效，请重试'), findsNothing);

    // A trailing slash is the same callback.
    const callback = NavigationRequest(
      url: 'techpie://auth-callback/?code=ok',
      isMainFrame: true,
    );
    expect(await delegate.navigate!(callback), NavigationDecision.prevent);
    expect(await delegate.navigate!(callback), NavigationDecision.prevent);
    await tester.pumpAndSettle();
    expect(result, callback.url);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Browser extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      delegate = _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) =>
      _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  final loads = <Uri>[];
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async => loads.add(params.uri);
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  NavigationRequestCallback? navigate;
  WebResourceErrorCallback? error;
  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback callback) async =>
      navigate = callback;
  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async => error = callback;
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
