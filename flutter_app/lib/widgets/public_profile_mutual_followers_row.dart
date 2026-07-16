import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import 'profile_avatar.dart';

/// Baris "Diikuti oleh X, Y, dan N lainnya" ala IG — avatar tumpuk +
/// nama di-bold. Dipakai SEMUA profil publik (bukan cuma official) di
/// atas latar surface terang.
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

  /// Spans dengan nama bold ala IG — bagian nama pakai w700, sisanya
  /// regular. Disusun dari string [copyFor] supaya copy tetap satu
  /// sumber kebenaran (dan test textContaining tetap match).
  static List<TextSpan> spansFor(
    PublicProfileMutualSummary summary, {
    required TextStyle base,
    required TextStyle emphasis,
  }) {
    final copy = copyFor(summary);
    if (copy.isEmpty) return const [];
    final names = summary.items.map((item) => item.name).take(2).toList();
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final name in names) {
      final index = copy.indexOf(name, cursor);
      if (index < 0) continue;
      if (index > cursor) {
        spans.add(TextSpan(text: copy.substring(cursor, index), style: base));
      }
      spans.add(TextSpan(text: name, style: emphasis));
      cursor = index + name.length;
    }
    if (cursor < copy.length) {
      spans.add(TextSpan(text: copy.substring(cursor), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (summary.items.isEmpty || summary.totalCount <= 0) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final previewItems = summary.items.take(3).toList(growable: false);
    final copy = copyFor(summary);
    final base = TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    final emphasis = TextStyle(
      color: cs.onSurface,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.5),
                      ),
                      child: ProfileAvatar(
                        initial: previewItems[index].name[0].toUpperCase(),
                        imageUrl: previewItems[index].profilePhotoUrl,
                        isOfficial: previewItems[index].isOfficial,
                        plain: true,
                        size: 27,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: spansFor(summary, base: base, emphasis: emphasis),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
