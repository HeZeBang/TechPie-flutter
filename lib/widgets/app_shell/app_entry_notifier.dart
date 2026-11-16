import 'package:flutter/foundation.dart';

import '../../features/campus_card/app/app_providers.dart';

/// A campus-card entry the host asked for — a home-screen widget tap, a
/// shortcut, a `techpie://ecard/pay` link — that has not been shown yet.
///
/// The shell and the glance surface both observe it; whichever is on screen
/// consumes it exactly once. It lives outside `app_shell.dart` so the glance
/// does not have to import the shell implementation.
final appShellPendingEcardEntry = ValueNotifier<CampusCardEntry?>(null);
