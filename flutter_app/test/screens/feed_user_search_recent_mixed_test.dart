import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/screens/feed_user_search_screen.dart';

Future<void> pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('recent campur: user & hashtag render + dismiss per-baris',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'feed_user_search_recent_v1::guest': <String>[
        jsonEncode({
          'type': 'user',
          'id': 'u1',
          'name': 'Rani',
          'username': 'rani_ap',
        }),
        jsonEncode({'type': 'hashtag', 'name': 'kucing', 'postCount': 3}),
      ],
    });
    await tester.pumpWidget(const MaterialApp(home: FeedUserSearchScreen()));
    await pumpBounded(tester);

    expect(find.text('rani_ap'), findsOneWidget);
    expect(find.text('#kucing'), findsOneWidget);
    expect(find.text('3 postingan'), findsOneWidget);

    // Dismiss entry hashtag via tombol X-nya; user tetap ada.
    await tester.tap(find.byKey(const ValueKey('recent-remove-hashtag:kucing')));
    await pumpBounded(tester);
    expect(find.text('#kucing'), findsNothing);
    expect(find.text('rani_ap'), findsOneWidget);
  });

  testWidgets('backward compat: entry lama tanpa type render sebagai user',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'feed_user_search_recent_v1::guest': <String>[
        jsonEncode({'id': 'u9', 'name': 'Lama', 'username': 'akunlama'}),
      ],
    });
    await tester.pumpWidget(const MaterialApp(home: FeedUserSearchScreen()));
    await pumpBounded(tester);
    expect(find.text('akunlama'), findsOneWidget);
  });
}
