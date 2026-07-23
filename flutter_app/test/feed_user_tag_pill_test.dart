import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/feed_user_tag_pill.dart';

void main() {
  const photo = Size(300, 400);
  const pill = Size(80, 28);

  test('anchor tengah → pill di bawah anchor, panah di atas pill', () {
    final p = placeTagPill(
        anchor: const Offset(150, 200), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isFalse);
    expect(p.topLeft.dx, 150 - 40); // center horizontal di anchor
    expect(p.topLeft.dy, greaterThan(200)); // badan di bawah titik
  });

  test('anchor dekat tepi kanan → badan di-clamp tetap utuh', () {
    final p = placeTagPill(
        anchor: const Offset(298, 200), pillSize: pill, photoSize: photo);
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
  });

  test('anchor dekat tepi bawah → flip: panah di bawah pill', () {
    final p = placeTagPill(
        anchor: const Offset(150, 396), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isTrue);
    expect(p.topLeft.dy + pill.height, lessThanOrEqualTo(photo.height));
  });

  test('anchor dekat tepi kiri → clamp kiri', () {
    final p = placeTagPill(
        anchor: const Offset(2, 200), pillSize: pill, photoSize: photo);
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
  });

  test('anchor pojok kanan-bawah → clamp x dan y sekaligus + flip', () {
    final p = placeTagPill(
        anchor: const Offset(299, 399), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isTrue);
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
    expect(p.topLeft.dy, greaterThanOrEqualTo(0));
  });

  test('anchor pojok kiri-atas → clamp x dan y, tidak flip', () {
    final p = placeTagPill(
        anchor: const Offset(1, 1), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isFalse);
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
    expect(p.topLeft.dy, greaterThanOrEqualTo(0));
  });

  test('anchor tepat di tengah foto persis 300x400', () {
    final p = placeTagPill(
        anchor: const Offset(150, 200), pillSize: pill, photoSize: photo);
    // sanity: hasil topLeft selalu dalam batas foto
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
    expect(p.topLeft.dy, greaterThanOrEqualTo(0));
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
  });

  test('pill lebih lebar dari foto tetap tidak crash (clamp aman)', () {
    final p = placeTagPill(
        anchor: const Offset(5, 5),
        pillSize: const Size(500, 28),
        photoSize: photo);
    expect(p.topLeft.dx.isFinite, isTrue);
  });
}
