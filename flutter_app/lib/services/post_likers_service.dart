import 'api_client.dart';
import 'follow_service.dart';

/// Fetch list user yang like sebuah post — backing data untuk IG-style
/// "Disukai oleh" bottom sheet. Pakai endpoint Next.js
/// `/api/feed/posts/[id]/likers` (cursor paginated, `isFollowing` per
/// row resolved batch di server supaya tidak ada N+1 round-trip per
/// row dari client).
///
/// Reuse `FollowUserSummary` dari `follow_service.dart` karena response
/// shape identical (id/name/username/profilePhotoUrl/bio/counts/
/// isFollowing/isSelf). Tidak perlu class PostLiker terpisah.
class PostLikersService {
  PostLikersService._();

  Future<FollowListResult> fetchLikers(
    String postId, {
    String? cursor,
    int limit = 20,
  }) async {
    final data = await apiClient.getJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/likers',
      query: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    if (data is Map<String, dynamic>) return FollowListResult.fromJson(data);
    if (data is Map) {
      return FollowListResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw const ApiException('Format response likers tidak valid.');
  }
}

final postLikersService = PostLikersService._();
