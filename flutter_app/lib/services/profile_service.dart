import 'package:flutter/foundation.dart';

import '../models/feed_post.dart';
import '../models/public_profile.dart';
import 'api_client.dart';

enum PublicProfileContentFilter {
  all('all'),
  video('video'),
  // Nama enum tetap `shoppable` (dipakai luas sejak Spec A, label UI sudah
  // "Ditandai") — hanya apiValue yang berubah ke `tagged` (Spec B, Task 4:
  // tab ini sekarang menampilkan post yang menandai user, bukan post
  // shopping). PENTING: server `content=shoppable` dan `content=tagged`
  // BUKAN alias — dua query BEDA (diverifikasi langsung di
  // app/api/u/[username]/route.ts + task-4-report.md, yang eksplisit
  // membantah klaim "alias" ini). `shoppable` di server tetap filter produk
  // lama (productId/taggedProducts, author-scoped); `tagged` adalah query
  // baru Spec B (taggedUsers.some, TIDAK author-scoped). Aman diganti ke
  // `tagged` karena tab ini sebelumnya di-short-circuit klien (Spec A) —
  // TIDAK PERNAH benar-benar mengirim `content=shoppable` ke server, jadi
  // tak ada app lama yang bergantung pada nilai lama ini.
  shoppable('tagged');

  final String apiValue;

  const PublicProfileContentFilter(this.apiValue);
}

/// Public profile service — fetch /api/u/{username}. Used by:
///   - PublicProfileScreen (deep link / tap @username di feed/komentar)
///   - share preview kalau ada featured CTA "view profile"
///
/// Endpoint: `GET /api/u/{username}?content=all|video|tagged&cursor=...`
/// Tidak butuh login (public endpoint), tapi kalau ada session, server
/// set `isOwner: true` saat session.sub == target.id supaya screen
/// bisa tampilkan tombol "Edit Profil" alih-alih "Bagikan".
class ProfileService {
  ProfileService._();

  Future<PublicProfileResult> fetchPublicProfile({
    required String username,
    String? cursor,
    int limit = 20,
    PublicProfileContentFilter content = PublicProfileContentFilter.all,
  }) async {
    final query = <String, String>{
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': limit.toString(),
      'content': content.apiValue,
    };
    final path = '/api/u/${Uri.encodeComponent(username)}';
    final data = await apiClient.getJson(path, query: query);
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Format response profile tidak valid.');
    }
    final userRaw = data['user'];
    if (userRaw is! Map<String, dynamic>) {
      throw const ApiException('Profile tidak ditemukan.', statusCode: 404);
    }
    final statsRaw = data['stats'];
    final stats = statsRaw is Map<String, dynamic> ? statsRaw : const {};
    final isOwner = data['isOwner'] == true;
    final isFollowing = data['isFollowing'] == true;
    final mutualFollowers =
        PublicProfileMutualSummary.fromJson(data['mutualFollowers']);
    final profile = PublicProfile.fromJson(userRaw, isOwner: isOwner).copyWith(
      postCount: (stats['postCount'] as num?)?.toInt() ?? 0,
      likedCount: (stats['likedCount'] as num?)?.toInt() ?? 0,
      followersCount: (stats['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (stats['followingCount'] as num?)?.toInt() ?? 0,
      isFollowing: isFollowing,
      mutualFollowers: mutualFollowers,
    );
    final itemsRaw = data['items'];
    final items = <FeedPost>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map<String, dynamic>) {
          try {
            // FeedPost.fromJson handles both shape /api/u/{username} (mediaItems,
            // type, status, dll) DAN shape reels feed.
            items.add(FeedPost.fromJson(item));
          } catch (e) {
            if (kDebugMode) debugPrint('[profile] post parse error: $e');
          }
        }
      }
    }
    return PublicProfileResult(
      profile: profile,
      posts: items,
      nextCursor: data['nextCursor'] as String?,
    );
  }
}

class PublicProfileResult {
  final PublicProfile profile;
  final List<FeedPost> posts;
  final String? nextCursor;

  const PublicProfileResult({
    required this.profile,
    required this.posts,
    this.nextCursor,
  });
}

final profileService = ProfileService._();
