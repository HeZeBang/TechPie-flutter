import 'package:flutter/material.dart';

import '../../models/oa_gym.dart';
import '../../theme/theme.dart';
import '../design_system/design_system.dart';

class GymMessageCard extends StatelessWidget {
  const GymMessageCard({
    super.key,
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final tint = isError ? colors.dangerRed : colors.infoBlue;
    return TpCard(
      color: tint.withValues(alpha: colors.isDark ? 0.16 : 0.08),
      borderColor: tint.withValues(alpha: 0.25),
      borderRadius: TpTokens.radiusS,
      padding: const EdgeInsets.all(TpTokens.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? TpIcons.info : TpIcons.checkCircle,
            size: TpTokens.iconS,
            color: tint,
          ),
          const SizedBox(width: TpTokens.space2),
          Expanded(
            child: Text(
              message,
              style: TpTypography.itemMeta(colors).copyWith(
                color: isError ? colors.dangerRed : colors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String gymFormatDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

IconData gymSportIcon(OaSport sport) => switch (sport) {
      OaSport.badminton => TpIcons.activity,
      OaSport.pingpong => TpIcons.circleDot,
      OaSport.tennis => TpIcons.activity,
      OaSport.pickleball => TpIcons.circleDot,
    };

const Set<String> _parentVenueNames = {
  '所有场地',
  '室内羽毛球场',
  '室内乒乓球场',
  '网球场',
  '匹克球场',
};

Map<OaSport, List<String>> gymVenuesBySport(
  Iterable<String> venues,
  Set<OaSport> sports,
) {
  final result = <OaSport, List<String>>{
    for (final sport in sports) sport: <String>[],
  };
  for (final item in venues) {
    if (_parentVenueNames.contains(item)) continue;
    for (final sport in sports) {
      if (oaVenueMatchesSport(item, sport)) result[sport]!.add(item);
    }
  }
  return result;
}

List<String> gymVenuesForSports(
  Iterable<String> venues,
  Set<OaSport> sports,
) =>
    venues
        .where(
          (venue) =>
              !_parentVenueNames.contains(venue) &&
              sports.any((sport) => oaVenueMatchesSport(venue, sport)),
        )
        .toList();
