import 'dart:io';

String _appProxy = '';

class TechPieHttpOverrides extends HttpOverrides {
  TechPieHttpOverrides([this._previous]);

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _previous?.createHttpClient(context) ??
        super.createHttpClient(context);
    // Read the current choice on every request, including existing clients.
    client.findProxy = (uri) => resolveAppProxyImpl(uri);
    return client;
  }
}

String resolveAppProxyImpl(Uri uri, {Map<String, String>? environment}) {
  if (_appProxy.isNotEmpty) return 'PROXY $_appProxy';
  return HttpClient.findProxyFromEnvironment(uri, environment: environment);
}

void configureAppProxyImpl(String normalizedProxy) {
  _appProxy = normalizedProxy;
  final current = HttpOverrides.global;
  if (current is! TechPieHttpOverrides) {
    HttpOverrides.global = TechPieHttpOverrides(current);
  }
}
