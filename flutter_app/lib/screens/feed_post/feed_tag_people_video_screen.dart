import 'package:flutter/material.dart';

import '../../models/new_post_user_tag.dart';

/// Layar pemilihan tag orang di VIDEO (Spec B) — STUB.
///
/// Video hanya butuh daftar nama (tanpa koordinat/mediaIndex — lihat
/// `lib/feed/tagged-users.ts` `parseTaggedUsersInput` cabang `isVideo`).
/// Task 8 hanya membangun entry point + plumbing upload (termasuk draft
/// persist/restore); UI pencarian akun diisi di Task 10. Stub ini sengaja
/// langsung mengembalikan `initialTags` tanpa perubahan.
class FeedTagPeopleVideoScreen extends StatelessWidget {
  final List<NewPostUserTag> initialTags;

  const FeedTagPeopleVideoScreen({super.key, required this.initialTags});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tandai Orang')),
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(initialTags),
          child: const Text('Kembali'),
        ),
      ),
    );
  }
}
