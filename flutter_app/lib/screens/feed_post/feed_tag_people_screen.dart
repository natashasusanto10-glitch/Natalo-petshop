import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/new_post_user_tag.dart';

/// Layar penempatan tag orang di FOTO (Spec B) — STUB.
///
/// Task 8 hanya membangun entry point + plumbing upload; penempatan tag
/// per-foto (search akun, drag pin, koordinat x/y) diisi di Task 9. Stub
/// ini sengaja langsung mengembalikan `initialTags` tanpa perubahan supaya
/// composer (`feed_new_post_screen.dart`) sudah bisa compile & terhubung
/// end-to-end sebelum Task 9 selesai.
class FeedTagPeopleScreen extends StatelessWidget {
  final List<File> photoFiles;
  final List<NewPostUserTag> initialTags;

  const FeedTagPeopleScreen({
    super.key,
    required this.photoFiles,
    required this.initialTags,
  });

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
