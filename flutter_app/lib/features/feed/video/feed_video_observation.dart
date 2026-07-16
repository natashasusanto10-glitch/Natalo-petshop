import 'social_video_session_observer.dart';

String feedPreloadOwnerId(String postId) => 'main-feed-preload-$postId';

String feedLocalOwnerId(String postId) => 'main-feed-view-$postId';

void observeFeedPreloadCreated(
  SocialVideoSessionObserver observer, {
  required String postId,
  required Object controller,
}) {
  _observe(
    observer,
    type: SocialVideoLifecycleType.created,
    postId: postId,
    ownerId: feedPreloadOwnerId(postId),
    controller: controller,
  );
}

void observeFeedPreloadAdopted(
  SocialVideoSessionObserver observer, {
  required String postId,
  required Object controller,
}) {
  _observe(
    observer,
    type: SocialVideoLifecycleType.attached,
    postId: postId,
    ownerId: feedLocalOwnerId(postId),
    controller: controller,
  );
}

void observeFeedLocalControllerCreated(
  SocialVideoSessionObserver observer, {
  required String postId,
  required Object controller,
}) {
  _observe(
    observer,
    type: SocialVideoLifecycleType.created,
    postId: postId,
    ownerId: feedLocalOwnerId(postId),
    controller: controller,
  );
}

void observeFeedControllerInitialized(
  SocialVideoSessionObserver observer, {
  required String postId,
  required Object controller,
  required String ownerId,
}) {
  _observe(
    observer,
    type: SocialVideoLifecycleType.initialized,
    postId: postId,
    ownerId: ownerId,
    controller: controller,
  );
}

void observeFeedControllerFailed(
  SocialVideoSessionObserver observer, {
  required String postId,
  required Object controller,
  required String ownerId,
}) {
  _observe(
    observer,
    type: SocialVideoLifecycleType.failed,
    postId: postId,
    ownerId: ownerId,
    controller: controller,
  );
  _observe(
    observer,
    type: SocialVideoLifecycleType.released,
    postId: postId,
    ownerId: ownerId,
    controller: controller,
  );
}

void observeFeedControllerDisposed(
  SocialVideoSessionObserver observer, {
  required String postId,
  required Object controller,
  required String ownerId,
}) {
  _observe(
    observer,
    type: SocialVideoLifecycleType.disposed,
    postId: postId,
    ownerId: ownerId,
    controller: controller,
  );
}

void _observe(
  SocialVideoSessionObserver observer, {
  required SocialVideoLifecycleType type,
  required String postId,
  required String ownerId,
  required Object controller,
}) {
  try {
    observer.observeController(
      type: type,
      postId: postId,
      surface: SocialVideoSurface.mainFeed,
      ownerId: ownerId,
      controllerIdentity: controller,
    );
  } catch (_) {
    // Passive diagnostics must never affect player lifecycle or ownership.
  }
}
