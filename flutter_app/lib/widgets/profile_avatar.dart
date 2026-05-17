import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

const _avatarBlue = Color(0xFF0B7FEA);

class ProfileAvatar extends StatelessWidget {
  final String initial;
  final String? imageUrl;
  final double size;
  final double fontSize;
  final bool showCameraBadge;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.initial,
    this.imageUrl,
    this.size = 72,
    this.fontSize = 28,
    this.showCameraBadge = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _AvatarContent(
            imageUrl: imageUrl,
            initial: initial,
            fontSize: fontSize,
          ),
        ),
        if (showCameraBadge)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              height: size * 0.32,
              width: size * 0.32,
              decoration: BoxDecoration(
                color: _avatarBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.photo_camera_rounded,
                color: Colors.white,
                size: size * 0.16,
              ),
            ),
          ),
      ],
    );

    if (onTap == null) return avatar;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: avatar,
      ),
    );
  }
}

class _AvatarContent extends StatelessWidget {
  final String? imageUrl;
  final String initial;
  final double fontSize;

  const _AvatarContent({
    required this.imageUrl,
    required this.initial,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _InitialAvatar(
            initial: initial,
            fontSize: fontSize,
          ),
        );
      }
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }
    return _InitialAvatar(initial: initial, fontSize: fontSize);
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initial;
  final double fontSize;

  const _InitialAvatar({required this.initial, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFFEAF5FF),
      child: Text(
        initial.isEmpty ? 'N' : initial,
        style: TextStyle(
          color: _avatarBlue,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
