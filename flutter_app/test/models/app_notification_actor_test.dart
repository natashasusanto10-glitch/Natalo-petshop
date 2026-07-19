import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';

void main() {
  Map<String, dynamic> base() => {
        'id': 'n', 'title': 'T', 'body': 'B', 'type': 'info',
        'createdAt': '2026-07-19T00:00:00.000Z', 'read': false,
      };
  test('parse actorAvatarUrl + actorName (camel & snake)', () {
    final a = AppNotification.fromApiJson(
        {...base(), 'actorAvatarUrl': 'https://cdn/a.jpg', 'actorName': 'Andi'});
    expect(a.actorAvatarUrl, 'https://cdn/a.jpg');
    expect(a.actorName, 'Andi');
    final b = AppNotification.fromApiJson(
        {...base(), 'actor_avatar_url': 'https://cdn/b.jpg', 'actor_name': 'Budi'});
    expect(b.actorAvatarUrl, 'https://cdn/b.jpg');
    expect(b.actorName, 'Budi');
  });
  test('null saat absent, survive copyWith', () {
    final a = AppNotification.fromApiJson(base());
    expect(a.actorAvatarUrl, isNull);
    final c = AppNotification.fromApiJson(
        {...base(), 'actorAvatarUrl': 'https://cdn/a.jpg'});
    expect(c.copyWith(read: true).actorAvatarUrl, 'https://cdn/a.jpg');
  });
}
