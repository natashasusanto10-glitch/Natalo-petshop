import 'package:flutter/material.dart';

import '../../models/new_post_user_tag.dart';
import '../../theme/natalo_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/profile_avatar.dart';
import 'feed_tag_people_screen.dart'
    show
        TagSearchUser,
        TagUserSearchFn,
        TagUserSearchPanel,
        defaultTagUserSearch;

const _kMaxTags = 20;

/// Layar pemilihan tag orang di VIDEO (Spec B) — daftar sederhana.
///
/// Video hanya butuh daftar nama (tanpa koordinat/mediaIndex — lihat
/// `lib/feed/tagged-users.ts` `parseTaggedUsersInput` cabang `isVideo`):
/// cari akun lewat [TagUserSearchPanel] yang sama dipakai varian foto →
/// tambah ke daftar → bisa dihapus. Semua `NewPostUserTag` yang dihasilkan
/// punya `mediaIndex`/`x`/`y` null.
class FeedTagPeopleVideoScreen extends StatefulWidget {
  final List<NewPostUserTag> initialTags;
  final TagUserSearchFn searchUsers;

  const FeedTagPeopleVideoScreen({
    super.key,
    this.initialTags = const [],
    this.searchUsers = defaultTagUserSearch,
  });

  @override
  State<FeedTagPeopleVideoScreen> createState() =>
      _FeedTagPeopleVideoScreenState();
}

class _FeedTagPeopleVideoScreenState extends State<FeedTagPeopleVideoScreen> {
  late List<NewPostUserTag> _tags = [...widget.initialTags];

  Future<void> _addPerson() async {
    if (_tags.length >= _kMaxTags) {
      AppToast.show(
        context,
        'Maksimal 20 orang per postingan.',
        kind: ToastKind.info,
      );
      return;
    }
    // Fade halus (sama seperti panel serupa di varian foto,
    // feed_tag_people_screen.dart) — dulu MaterialPageRoute fullscreenDialog
    // polos, satu-satunya jalur "Tandai Orang" yang belum konsisten.
    final picked = await Navigator.of(context).push<TagSearchUser>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) =>
            TagUserSearchPanel(searchUsers: widget.searchUsers),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (picked == null || !mounted) return;
    if (_tags.any((t) => t.userId == picked.id)) return; // unik per post
    setState(() {
      _tags = [
        ..._tags,
        NewPostUserTag(
          userId: picked.id,
          username: picked.username,
          name: picked.name,
          profilePhotoUrl: picked.profilePhotoUrl,
        ),
      ];
    });
  }

  void _removePerson(NewPostUserTag tag) {
    setState(() {
      _tags = _tags.where((t) => t.userId != tag.userId).toList();
    });
  }

  void _onDone() {
    Navigator.of(context).pop(List<NewPostUserTag>.of(_tags));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Tandai Orang'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Semantics(
                button: true,
                label: 'Selesai menandai',
                child: GestureDetector(
                  onTap: _onDone,
                  behavior: HitTestBehavior.opaque,
                  // Hit target 44dp (checklist tap-target) — lingkaran
                  // visual tetap 36px, ter-pusat (audit polish lanjutan).
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: NataloColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading:
                Icon(Icons.person_add_alt_1_outlined, color: cs.onSurface),
            title: const Text('Tambah orang'),
            onTap: _addPerson,
          ),
          for (final tag in _tags)
            ListTile(
              key: ValueKey(tag.userId),
              leading: ProfileAvatar(
                imageUrl: tag.profilePhotoUrl,
                initial: tag.username.isNotEmpty
                    ? tag.username[0].toUpperCase()
                    : '?',
                size: 40,
              ),
              title: Text(tag.username),
              subtitle: tag.name.isNotEmpty ? Text(tag.name) : null,
              trailing: Semantics(
                button: true,
                label: 'Hapus ${tag.username}',
                child: GestureDetector(
                  onTap: () => _removePerson(tag),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(Icons.close,
                          size: 20, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
