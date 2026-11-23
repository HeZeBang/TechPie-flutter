/// Shared by campus authentication and session probes. The app supplies its
/// actual version, OS and display scale before starting any network requests.
class CampusUserAgent {
  static String value = 'TechPie';

  static String format({
    required String version,
    required String build,
    required String device,
    required String system,
    required String systemVersion,
    required double scale,
  }) =>
      'TechPie/$version.$build ($device; $system $systemVersion; Scale/${scale.toStringAsFixed(2)}) techpie/$version';
}
