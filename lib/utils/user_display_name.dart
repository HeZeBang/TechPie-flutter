import 'dart:convert';

import '../models/user_session.dart';

/// Reads `displayName` and `name` claims from a Casdoor JWT access token without
/// verifying its signature or throwing on non-JWT strings.
({String? displayName, String? username}) parseCasdoorJwtNameClaims(String? jwt) {
  if (jwt == null || jwt.isEmpty) {
    return (displayName: null, username: null);
  }
  final parts = jwt.split('.');
  if (parts.length != 3 || parts[1].isEmpty) {
    return (displayName: null, username: null);
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map<Object?, Object?>) {
      return (displayName: null, username: null);
    }
    final displayName = _nonEmptyTrimmed(decoded['displayName']?.toString());
    final username = _nonEmptyTrimmed(decoded['name']?.toString());
    return (displayName: displayName, username: username);
  } catch (_) {
    return (displayName: null, username: null);
  }
}

/// Returns a display name from Casdoor JWT claims when the stored session name
/// is missing or only reflects the Casdoor login username (`name`).
String? casdoorDisplayNameFromJwt(
  String? jwt, {
  String? currentSessionUserName,
}) {
  final claims = parseCasdoorJwtNameClaims(jwt);
  final displayName = claims.displayName;
  if (displayName == null) return null;
  final current = _nonEmptyTrimmed(currentSessionUserName);
  if (current == null || current == claims.username) {
    return displayName;
  }
  return null;
}

/// Resolves the best available user display name, preferring authoritative
/// campus real-name sources over login handles while staying strictly scoped to
/// the active signed-in [session].
String resolveUserDisplayName({
  required UserSession? session,
  String? idsRealName,
  String? campusCardOwnerName,
}) {
  if (session == null) return '';

  final idsName = _nonEmptyTrimmed(idsRealName);
  if (idsName != null) return idsName;

  final cardName = _nonEmptyTrimmed(campusCardOwnerName);
  if (cardName != null) return cardName;

  final jwtDisplayName = casdoorDisplayNameFromJwt(
    session.geekpieToken,
    currentSessionUserName: session.userName,
  );
  if (jwtDisplayName != null) return jwtDisplayName;

  final sessionName = _nonEmptyTrimmed(session.userName);
  if (sessionName != null) return sessionName;

  return _nonEmptyTrimmed(session.userId) ?? '';
}

/// Derives a compact avatar label matching existing TechPie CJK/ASCII rules.
String userAvatarLabel(String displayName) {
  final name = displayName.trim();
  if (name.isEmpty) return 'GP';
  final runes = name.runes.toList();
  if (runes.first > 127) {
    return String.fromCharCode(runes.first);
  }
  return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
}

String? _nonEmptyTrimmed(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
