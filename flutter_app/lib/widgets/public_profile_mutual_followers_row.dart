import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import 'profile_avatar.dart';

class PublicProfileMutualFollowersRow extends StatelessWidget {
  final PublicProfileMutualSummary summary;

  const PublicProfileMutualFollowersRow({
    super.key,
    required this.summary,
  });

  static String copyFor(PublicProfileMutualSummary summary) {
    final names = summary.items.map((item) => item.name).take(2).toList();
    if (names.isEmpty) return '';
    if (summary.totalCount <= 1) return 'Diikuti oleh ${names.first}';
    if (summary.totalCount == 2 && names.length == 2) {
      return 'Diikuti oleh ${names.first} dan ${names.last}';
    }
    final remaining = summary.totalCount - names.length;
    return 'Diikuti oleh ${names.join(', ')}, dan $remaining lainnya';
  }

  @override
  Widget build(BuildContext context) {
    if (summary.items.isEmpty || summary.totalCount <= 0) {
      return const SizedBox.shrink();
    }
    final previewItems = summary.items.take(3).toList(growable: false);
    final copy = copyFor(summary);
    return Semantics(
      label: copy,
      excludeSemantics: true,
      child: Row(
        key: const Key('official_mutual_row'),
        children: [
          SizedBox(
            width: 58,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var index = 0; index < previewItems.length; index++)
                  Positioned(
                    left: index * 18,
                    child: ProfileAvatar(
                      initial: previewItems[index].name[0].toUpperCase(),
                      imageUrl: previewItems[index].profilePhotoUrl,
                      isOfficial: previewItems[index].isOfficial,
                      plain: true,
                      size: 30,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              copy,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
