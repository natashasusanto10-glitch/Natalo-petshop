part of 'member_reviews_screen.dart';

class _ReviewDraft {
  final content = TextEditingController();
  final List<ProductReviewMedia> media = [];
  final Set<String> suggestions = {};
  int rating = 0;
  bool uploading = false;
  bool expanded = false;
  String? error;
}

Future<_SubmittedReview> _sendReviewDraft(
    ReviewableItem item, _ReviewDraft draft) async {
  final rating = draft.rating;
  final content = draft.content.text.trim();
  final media = List<ProductReviewMedia>.unmodifiable(draft.media);
  try {
    final result = await reviewService.submitReview(
        productId: item.productId,
        orderItemId: item.orderItemId,
        rating: rating,
        content: content.isEmpty ? null : content,
        imageUrls: media
            .where((media) => !media.isVideo)
            .map((media) => media.url)
            .toList(),
        media: media);
    return _SubmittedReview(
        rating: rating,
        content: content,
        media: media,
        pointsAwarded: result.pointsAwarded);
  } on ApiException {
    // A timeout can happen after the server saved a review. Reconcile that
    // order line before retrying; never count bonus points twice.
    try {
      final remote = await reviewService.fetchReviewableItems();
      for (final row in remote) {
        if (row.orderItemId == item.orderItemId && row.hasReviewed) {
          return _SubmittedReview(
              rating: row.reviewRating ?? rating,
              content: row.reviewText,
              media: row.reviewMedia);
        }
      }
    } catch (_) {/* Preserve the original failure and its draft. */}
    rethrow;
  }
}

class _PendingReviewList extends StatelessWidget {
  const _PendingReviewList(
      {super.key,
      required this.items,
      required this.onReview,
      required this.onReviewAll,
      required this.onHistory});
  final List<ReviewableItem> items;
  final ValueChanged<ReviewableItem> onReview;
  final ValueChanged<List<ReviewableItem>> onReviewAll;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(children: [
        const _ReviewEmptyState(
            icon: Icons.verified_rounded,
            title: 'Semua produk sudah diulas',
            body: 'Terima kasih sudah berbagi pengalaman.'),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: onHistory, child: const Text('Lihat ulasan saya')),
      ]);
    }
    final groups = <String, List<ReviewableItem>>{};
    for (final item in items) {
      (groups[item.orderNumber ?? item.orderItemId] ??= []).add(item);
    }
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      for (final entry in groups.entries)
        Padding(
            key: ValueKey(entry.key),
            padding: const EdgeInsets.only(bottom: 20),
            child: AnimatedSize(
              duration: MotionPrefs.shouldReduce(context)
                  ? Duration.zero
                  : AppMotionTokens.standard,
              curve: AppMotionTokens.curveEmphasized,
              alignment: Alignment.topCenter,
              child: Container(
                decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant)),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(_formatDate(entry.value.first.orderDate),
                                  style: const TextStyle(
                                      fontSize: NataloTextSize.bodyLg,
                                      fontWeight: NataloWeight.strong)),
                              if (entry.value.first.orderNumber != null) ...[
                                const SizedBox(height: 4),
                                Text(entry.key,
                                    style: TextStyle(
                                        fontSize: NataloTextSize.caption,
                                        color: cs.onSurfaceVariant)),
                              ],
                            ])),
                        const SizedBox(width: 12),
                        FilledButton(
                            onPressed: () => onReviewAll(entry.value),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 48)),
                            child: Text('Ulas semua (${entry.value.length})')),
                      ])),
                  for (final item in entry.value) ...[
                    Divider(height: 1, color: cs.outlineVariant),
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _ReviewSheetProductPreview(item: item),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: Text('Belum diulas',
                                    style: TextStyle(
                                        fontSize: NataloTextSize.caption,
                                        color: cs.onSurfaceVariant))),
                            OutlinedButton(
                                onPressed: () => onReview(item),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48)),
                                child: const Text('Beri ulasan'))
                          ]),
                        ])),
                  ],
                ]),
              ),
            )),
    ]);
  }
}

class _ReviewSessionSheet extends StatefulWidget {
  const _ReviewSessionSheet(
      {required this.items,
      required this.drafts,
      required this.pickupContext,
      required this.onSubmitted});
  final List<ReviewableItem> items;
  final Map<String, _ReviewDraft> drafts;
  final bool? Function(ReviewableItem) pickupContext;
  final void Function(ReviewableItem, _SubmittedReview) onSubmitted;
  @override
  State<_ReviewSessionSheet> createState() => _ReviewSessionSheetState();
}

class _ReviewSessionSheetState extends State<_ReviewSessionSheet> {
  late final List<ReviewableItem> _remaining = List.of(widget.items);
  bool _sending = false;
  int _completed = 0;
  int _points = 0;
  int _massRating = 0;
  bool get _uploading => widget.drafts.values.any((draft) => draft.uploading);
  _ReviewDraft _draft(ReviewableItem item) => widget.drafts[item.orderItemId]!;

  Future<void> _submit() async {
    if (_sending ||
        _uploading ||
        _remaining.any((item) => _draft(item).rating == 0)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sending = true;
      for (final item in _remaining) {
        _draft(item).error = null;
      }
    });
    for (final item in List.of(_remaining)) {
      try {
        final submitted = await _sendReviewDraft(item, _draft(item));
        if (!mounted) return;
        widget.onSubmitted(item, submitted);
        setState(() {
          _remaining.remove(item);
          _completed++;
          _points += submitted.pointsAwarded;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _draft(item).error = error is ApiException
            ? error.message
            : error is ReadOnlyModeException
                ? 'Mode aman aktif. Ulasan tidak dikirim.'
                : 'Ulasan belum terkirim. Coba lagi.');
        if (error is ReadOnlyModeException) break;
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (_remaining.isEmpty) {
      unawaited(HapticFeedback.mediumImpact());
      Navigator.pop(context, _points);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MotionPrefs.shouldReduce(context);
    final ready = _remaining.where((item) => _draft(item).rating > 0).length;
    final failed = _remaining.any((item) => _draft(item).error != null);
    return PopScope(
      canPop: !_sending && !_uploading,
      child: AnimatedPadding(
        duration: reduce ? Duration.zero : AppMotionTokens.quick,
        curve: AppMotionTokens.curveEnter,
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .94),
          decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28))),
          child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 12),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(4))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('SATU PESANAN · SATU SESI',
                                style: TextStyle(
                                    fontSize: NataloTextSize.micro,
                                    color: cs.primary)),
                            const SizedBox(height: 8),
                            Text('Ulas ${_remaining.length} produk',
                                style: const TextStyle(
                                    fontSize: NataloTextSize.headline,
                                    fontWeight: NataloWeight.strong)),
                          ])),
                      IconButton(
                          tooltip: 'Tutup',
                          onPressed: _sending || _uploading
                              ? null
                              : () => Navigator.pop(
                                  context, _completed > 0 ? _points : null),
                          icon: const Icon(Icons.close_rounded)),
                    ])),
                Divider(height: 1, color: cs.outlineVariant),
                Flexible(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (failed)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                                color: cs.errorContainer,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Text(
                                                _completed > 0
                                                    ? '$_completed ulasan terkirim. ${_remaining.length} belum terkirim. Draft tetap tersimpan.'
                                                    : 'Ulasan belum terkirim. Draft tetap tersimpan.',
                                                style: TextStyle(
                                                    color: cs.onErrorContainer,
                                                    height: 1.5))))),
                              if (_remaining.length > 1) ...[
                                const Text('Rating semua produk',
                                    style: TextStyle(
                                        fontSize: NataloTextSize.bodyLg,
                                        fontWeight: NataloWeight.strong)),
                                const SizedBox(height: 6),
                                Text('Pilih sekali. Bisa diubah per produk.',
                                    style: TextStyle(
                                        fontSize: NataloTextSize.caption,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 28),
                                PremiumStarRating(
                                    value: _massRating,
                                    enabled: !_sending && !_uploading,
                                    onChanged: (rating) => setState(() {
                                          _massRating = rating;
                                          for (final item in _remaining) {
                                            _draft(item).rating = rating;
                                          }
                                        })),
                                const SizedBox(height: 12),
                                Divider(color: cs.outlineVariant),
                              ],
                              for (var index = 0;
                                  index < _remaining.length;
                                  index++)
                                Padding(
                                    key:
                                        ValueKey(_remaining[index].orderItemId),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child:
                                        _draftCard(_remaining[index], index)),
                            ]))),
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(children: [
                      TweenAnimationBuilder<double>(
                          tween: Tween(
                              end: _remaining.isEmpty
                                  ? 1
                                  : ready / _remaining.length),
                          duration:
                              reduce ? Duration.zero : AppMotionTokens.standard,
                          builder: (_, value, __) => LinearProgressIndicator(
                              value: value, minHeight: 3)),
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text(
                              _sending
                                  ? '$_completed dari ${widget.items.length} ulasan terkirim'
                                  : '$ready dari ${_remaining.length} produk sudah diberi rating',
                              style: TextStyle(
                                  fontSize: NataloTextSize.caption,
                                  color: cs.onSurfaceVariant))),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: _sending ||
                                      _uploading ||
                                      ready != _remaining.length
                                  ? null
                                  : _submit,
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52)),
                              child: _sending
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                          SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2)),
                                          SizedBox(width: 10),
                                          Text('Mengirim…')
                                        ])
                                  : Text(
                                      '${failed ? 'Kirim ulang' : 'Kirim'} ${_remaining.length} ulasan'))),
                    ])),
              ])),
        ),
      ),
    );
  }

  Widget _draftCard(ReviewableItem item, int index) {
    final draft = _draft(item);
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Produk ${index + 1} dari ${_remaining.length}',
                style: TextStyle(
                    fontSize: NataloTextSize.caption,
                    color: cs.onSurfaceVariant))),
        if (draft.rating > 0)
          const Icon(Icons.check_rounded, size: 18, color: _successGreen)
      ]),
      const SizedBox(height: 12),
      _ReviewSheetProductPreview(item: item, showPrice: false),
      const SizedBox(height: 28),
      PremiumStarRating(
          value: draft.rating,
          enabled: !_sending && !_uploading,
          onChanged: (rating) => setState(() {
                draft.rating = rating;
                _massRating = 0;
              })),
      const SizedBox(height: 8),
      Text(draft.rating == 0 ? 'Belum dipilih' : _ratingLabel(draft.rating),
          style: TextStyle(
              fontSize: NataloTextSize.caption, color: cs.onSurfaceVariant)),
      if (draft.error != null)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(draft.error!,
                style:
                    TextStyle(color: cs.error, fontSize: NataloTextSize.body))),
      TextButton(
          onPressed: _sending || _uploading
              ? null
              : () => setState(() => draft.expanded = !draft.expanded),
          style: TextButton.styleFrom(
              minimumSize: const Size(48, 48), padding: EdgeInsets.zero),
          child: Text(draft.expanded
              ? 'Tutup komentar & foto'
              : '+ Komentar & foto · opsional')),
      Visibility(
          visible: draft.expanded,
          maintainState: true,
          child: _ReviewSubmitSheet(
              key: ValueKey('editor-${item.orderItemId}'),
              item: item,
              draft: draft,
              embedded: true,
              enabled: !_sending,
              isSelfPickup: widget.pickupContext(item),
              onChanged: () {
                if (mounted) setState(() {});
              })),
      const SizedBox(height: 12),
      Divider(color: cs.outlineVariant),
    ]);
  }
}
