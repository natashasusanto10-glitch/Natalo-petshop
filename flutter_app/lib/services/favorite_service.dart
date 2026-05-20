import '../utils/read_only_mode.dart';
import 'api_client.dart';

class FavoriteService {
  Future<Set<String>> fetchFavoriteIds() async {
    final data = await apiClient.getJson('/api/member/favorites');
    // BUG FIX: backend GET /api/member/favorites return plain List<String>
    // (lihat app/api/member/favorites/route.ts:17 —
    // `NextResponse.json(favorites.map((f) => f.productId))`),
    // BUKAN envelope { data: [...] }. Pattern lama `data['data']`
    // throw runtime di Dart (List tidak accept String key) → exception
    // bubble up unhandled di ensureLoaded() fire-and-forget → _loaded
    // stuck false → wishlist tampak tidak save padahal POST sukses.
    //
    // Fix: try plain List dulu, fallback ke envelope kalau backend
    // berubah suatu saat (defensive parsing).
    if (data is List) {
      return data
          .map((item) => item.toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    }
    if (data is Map<String, dynamic>) {
      final raw = data['data'];
      if (raw is List) {
        return raw
            .map((item) => item.toString())
            .where((id) => id.isNotEmpty)
            .toSet();
      }
    }
    return {};
  }

  Future<void> addFavorite(String productId) async {
    readOnlyMode.assertWritable('wishlist_add');
    await apiClient.postJson(
      '/api/member/favorites',
      body: {'productId': productId},
    );
  }

  Future<void> removeFavorite(String productId) async {
    readOnlyMode.assertWritable('wishlist_remove');
    await apiClient.deleteJson(
      '/api/member/favorites/${Uri.encodeComponent(productId)}',
    );
  }
}

final favoriteService = FavoriteService();
