bool preloadSlotOccupied<C extends Object, W extends Object>(
  String id,
  Map<String, C> controllers,
  Map<String, W> wrappers,
) {
  return controllers.containsKey(id) || wrappers.containsKey(id);
}

/// Clears only the failed generation currently registered for [id].
bool removeFailedPreloadGeneration<C extends Object, W extends Object>({
  required String id,
  required W failedWrapper,
  required C failedController,
  required Map<String, C> controllers,
  required Map<String, W> wrappers,
}) {
  if (!identical(wrappers[id], failedWrapper)) return false;
  wrappers.remove(id);
  if (identical(controllers[id], failedController)) controllers.remove(id);
  return true;
}
