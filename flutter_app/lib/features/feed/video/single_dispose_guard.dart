/// Identity-based, non-retaining guard for async native resource disposal.
class SingleDisposeGuard<T extends Object> {
  final Expando<bool> _disposed = Expando<bool>();

  Future<void> dispose(T resource, Future<void> Function() disposer) async {
    if (_disposed[resource] == true) return;
    _disposed[resource] = true;
    try {
      await disposer();
    } catch (_) {}
  }
}
