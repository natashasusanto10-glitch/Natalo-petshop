import '../utils/read_only_mode.dart';
import 'api_client.dart';

class FavoriteService {
  Future<Set<String>> fetchFavoriteIds() async {
    final data = await apiClient.getJson('/api/member/favorites');
    final raw = data['data'];
    if (raw is! List) return {};
    return raw
        .map((item) => item.toString())
        .where((id) => id.isNotEmpty)
        .toSet();
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
