import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/campus_card/app/app_runtime.dart';
import 'features/campus_card/app/real_runtime_factory.dart';
import 'features/campus_card/core/config/app_environment.dart';
import 'features/campus_card/data/auth/geekpie_ecard_session_issuer.dart';
import 'features/campus_card/domain/ports/bill_ports.dart';
import 'services/api_base_url.dart';
import 'services/spending_alert_service.dart';
import 'services/storage_service.dart';

/// A short-lived, activity-free ledger check; never creates a foreground service.
Future<void> runSpendingBackgroundRefresh() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppRuntime? runtime;
  SpendingAlertService? alerts;
  var success = false;
  try {
    final storage = StorageService(await SharedPreferences.getInstance());
    alerts = SpendingAlertService(storage);
    success = await alerts.refreshInBackground(() async {
      final card = buildRealRuntime(
        AppEnvironment.production,
        sessionIssuer: GeekPieEcardSessionIssuer(
          endpoint: () => Uri.parse('${apiBaseUrl(storage)}/auth/third-party/ecard'),
        ),
      );
      runtime = card;
      final history = card.transactions;
      if (history is! DateRangeTransactionHistoryPort) return [];
      final page = await (history as DateRangeTransactionHistoryPort).timelineRange(pageSize: 50);
      return page.items;
    });
  } catch (_) {
    // The worker can retry after a transient network/secure-storage failure.
  } finally {
    alerts?.dispose();
    try {
      await runtime?.dispose();
    } catch (_) {/* The engine is also torn down. */}
    try {
      await const MethodChannel('techpie/spending_worker')
          .invokeMethod<bool>('done', {'success': success});
    } on PlatformException {
      // The worker was cancelled or timed out.
    } on MissingPluginException {
      // No background Android host.
    }
  }
}
