import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/feed_provider.dart';
import '../widgets/feed_video_card.dart';

// Mirror of components/feed/FeedClient.tsx.
//
// Web uses CSS scroll-snap (snap-y snap-mandatory) inside a max-w-2xl
// container, with a JS snap-back hack for iOS WKWebView. Flutter equivalent
// is PageView.builder(scrollDirection: Axis.vertical) — native momentum,
// no JS hack needed.
//
// Triggers loadMore() when within 2 cards of the end (matches web prefetch
// distance for the medium memory tier — virtual window 2).

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController()
      ..addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _pageCtrl
      ..removeListener(_onPageScroll)
      ..dispose();
    super.dispose();
  }

  void _onPageScroll() {
    final pos = _pageCtrl.position;
    if (!pos.hasContentDimensions) return;
    final page = _pageCtrl.page;
    if (page == null) return;
    final idx = page.round();
    final currentActive = ref.read(activeVideoIndexProvider);
    if (idx != currentActive) {
      ref.read(activeVideoIndexProvider.notifier).state = idx;
    }
    // Prefetch trigger: within 2 cards of end
    final list = ref.read(feedListProvider).valueOrNull;
    if (list != null &&
        list.hasMore &&
        !list.loadingMore &&
        idx >= list.posts.length - 2) {
      ref.read(feedListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(feedListProvider);
    final activeIdx = ref.watch(activeVideoIndexProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: asyncList.when(
        loading: () => const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gagal memuat feed: $e',
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(feedListProvider.notifier).refresh(),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (state) {
          if (state.posts.isEmpty) {
            return const Center(
              child: Text('Belum ada post di feed',
                  style: TextStyle(color: Colors.white)),
            );
          }
          return RefreshIndicator.adaptive(
            onRefresh: () => ref.read(feedListProvider.notifier).refresh(),
            child: PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              itemCount: state.posts.length,
              itemBuilder: (_, i) => FeedVideoCard(
                post: state.posts[i],
                isActive: i == activeIdx,
              ),
            ),
          );
        },
      ),
    );
  }
}
