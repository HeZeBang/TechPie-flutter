import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../features/campus_card/domain/models/card_models.dart';
import '../../models/assignment_overrides.dart';
import '../assignment_service.dart';
import '../auth_service.dart';
import '../campus_card_service.dart';
import '../third_party_auth_service.dart';
import 'wear_protocol.dart';

class TechPieWearDataSource implements WearDataSource {
  TechPieWearDataSource({
    required this.auth,
    required this.accounts,
    required this.assignments,
    required this.campusCard,
    this.reminderOffsets = const [Duration(hours: 1)],
  });
  final AuthService auth;
  final ThirdPartyAuthService accounts;
  final AssignmentService assignments;
  final CampusCardService campusCard;

  /// Product default: one hour before each open deadline; opt-in at WearLink.open.
  final List<Duration> reminderOffsets;

  @override
  Future<WearAccount> account() async {
    final session = auth.session;
    if (session == null) throw const WearFailure('ACCOUNT_NOT_READY');
    final campus = accounts.cpdailyNode.account;
    // Use a single identity source for both fields, never combine unrelated accounts.
    final name = campus == null ? session.userName : campus.name ?? '';
    final studentId = campus == null ? session.studentId : campus.sid ?? '';
    final ecardId = await campusCard.readOpenId();
    return WearAccount(
      scope:
          jsonEncode([session.userId, campus?.account, campus?.sid, ecardId]),
      name: name,
      studentId: studentId,
    )..toJson();
  }

  @override
  Future<List<WearDdl>> deadlines() async {
    if (assignments.loading) {
      throw const WearFailure('PEER_NOT_READY', retryable: true);
    }
    if (assignments.error != null || assignments.platformErrors.isNotEmpty) {
      throw const WearFailure('SERVICE_UNAVAILABLE', retryable: true);
    }
    return assignments.visibleAssignments.map((assignment) {
      final id = sha256
          .convert(utf8.encode(AssignmentOverrides.keyFor(assignment)))
          .toString();
      final complete = assignments.isCompleted(assignment);
      return WearDdl(
        id: id,
        title: _truncate(assignment.title, 80),
        courseName: _truncate(assignment.course, 40),
        dueAt: assignment.due.toUtc(),
        completed: complete,
        remindAt: complete
            ? []
            : reminderOffsets
                .take(3)
                .map((offset) => assignment.due.subtract(offset).toUtc())
                .toList(),
      );
    }).toList();
  }

  @override
  Future<WearCampusCode> campusCode(String purpose) async {
    if (purpose != 'campus') throw const WearFailure('UNSUPPORTED_PURPOSE');
    final before = await account();
    final card = await campusCard.runtime.cards.currentCard();
    if (card == null || !card.status.permitsPayment) {
      throw const WearFailure('ACCOUNT_NOT_READY');
    }
    // Existing eCard is independently bound: only display for the same named campus account.
    if (card.ownerName.trim() != before.name.trim()) {
      throw const WearFailure('ACCOUNT_NOT_READY');
    }
    final frame = await campusCard.runtime.paymentCodes.generateOnlineCode();
    final after = await account();
    if (before.scope != after.scope) {
      throw const WearFailure('SESSION_MISMATCH');
    }
    // Binary eCard payloads are stored as Latin-1 by the existing QR codec.
    // Other online payloads are textual and use their original UTF-8 representation.
    final bytes = frame.rawQrCode.startsWith('5638')
        ? latin1.encode(frame.qrPayload)
        : utf8.encode(frame.qrPayload);
    return WearCampusCode(
      bytes: Uint8List.fromList(bytes),
      issuedAt: frame.generatedAt,
      validUntil: frame.generatedAt.add(const Duration(seconds: 30)),
    );
  }

  String _truncate(String value, int count) =>
      String.fromCharCodes(value.runes.take(count));
}
