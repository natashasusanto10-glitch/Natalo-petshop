import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/share_content.dart';
import 'app_analytics.dart';
import 'share_link_builder.dart';

abstract interface class PlatformShareGateway {
  Future<ShareResultStatus> share(SharePayload payload, {Rect? origin});
}

class _NativePlatformShareGateway implements PlatformShareGateway {
  const _NativePlatformShareGateway();

  @override
  Future<ShareResultStatus> share(SharePayload payload, {Rect? origin}) async {
    // share_plus 13: Share.share deprecated -> SharePlus.instance.share.
    final result = await SharePlus.instance.share(ShareParams(
      text: payload.text,
      subject: payload.subject,
      sharePositionOrigin: origin,
    ));
    return result.status;
  }
}

/// One native share-sheet bridge for every public Natalo link.
///
/// The launcher owns platform result handling; callers only provide safe
/// public content and, when applicable, their successful-share side effect.
class ShareSheetLauncher {
  ShareSheetLauncher({
    ShareLinkBuilder? linkBuilder,
    PlatformShareGateway? gateway,
  })  : _linkBuilder = linkBuilder ?? const ShareLinkBuilder(),
        _gateway = gateway ?? const _NativePlatformShareGateway();

  final ShareLinkBuilder _linkBuilder;
  final PlatformShareGateway _gateway;

  Future<ShareResultStatus> launch(
    ShareContent content, {
    Rect? origin,
    FutureOr<void> Function()? onCompleted,
  }) {
    return launchPayload(
      _linkBuilder.build(content),
      origin: origin,
      onCompleted: onCompleted,
      contentType: _contentType(content),
      contentId: _contentId(content),
    );
  }

  Future<ShareResultStatus> launchPayload(
    SharePayload payload, {
    PlatformShareGateway? gateway,
    Rect? origin,
    FutureOr<void> Function()? onCompleted,
    String contentType = 'unknown',
    String contentId = 'unknown',
  }) async {
    unawaited(AppAnalytics.logShareSheetOpened(
      contentType: contentType,
      contentId: contentId,
    ));
    final status = await (gateway ?? _gateway).share(payload, origin: origin);
    if (status == ShareResultStatus.success) {
      if (onCompleted != null) await onCompleted();
      unawaited(AppAnalytics.logShareCompleted(
        contentType: contentType,
        contentId: contentId,
      ));
    } else {
      unawaited(AppAnalytics.logShareDismissed(
        contentType: contentType,
        contentId: contentId,
        result: status.name,
      ));
    }
    return status;
  }

  static String _contentType(ShareContent content) => switch (content) {
        FeedShareContent() => 'feed',
        ProductShareContent() => 'product',
        ProfileShareContent() => 'profile',
      };

  static String _contentId(ShareContent content) => switch (content) {
        FeedShareContent(:final postId) => postId,
        ProductShareContent(:final slug) => slug,
        ProfileShareContent(:final username) => username,
      };
}

/// iPad requires the native share sheet to have an anchor rectangle. Android
/// ignores it, so this is safe to pass from every Flutter share surface.
Rect? shareOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
