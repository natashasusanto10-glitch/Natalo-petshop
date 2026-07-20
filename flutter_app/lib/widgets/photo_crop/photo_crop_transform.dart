import 'package:flutter/material.dart';

/// Mutable transform state untuk pan/zoom crop preview.
///
/// Extend [ChangeNotifier] supaya `ListenableBuilder` di [PhotoCropPreview]
/// bisa rebuild HANYA layer Transform saat user pinch — bukan whole
/// LayoutBuilder subtree (Image, ClipRect, dst). Big win untuk smoothness
/// gesture di lower-end devices.
///
/// Model koordinat: [scale] ∈ [1, 4]; [offsetFraction] = offset piksel
/// dibagi ukuran frame (jadi resolution-independent — dipakai apa adanya
/// oleh `processPhotoInIsolate` untuk rekonstruksi crop window tanpa perlu
/// tahu ukuran frame preview yang sebenarnya).
///
/// Dipakai bersama oleh feed media picker (aspect 4:5) dan profile photo
/// picker (aspect 1:1). Murni data holder — physics (fling/rubber-band)
/// hidup di state [PhotoCropPreview], bukan di sini, supaya class ini tetap
/// ringan & gampang di-test.
class PhotoCropTransform extends ChangeNotifier {
  double _scale = 1;
  Offset _offsetFraction = Offset.zero;

  double get scale => _scale;
  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    notifyListeners();
  }

  Offset get offsetFraction => _offsetFraction;
  set offsetFraction(Offset value) {
    if (_offsetFraction == value) return;
    _offsetFraction = value;
    notifyListeners();
  }

  /// Batch update — single notify untuk dua-duanya. Hindari double rebuild
  /// per gesture frame.
  void update({required double scale, required Offset offsetFraction}) {
    var changed = false;
    if (_scale != scale) {
      _scale = scale;
      changed = true;
    }
    if (_offsetFraction != offsetFraction) {
      _offsetFraction = offsetFraction;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void reset() {
    update(scale: 1, offsetFraction: Offset.zero);
  }
}
