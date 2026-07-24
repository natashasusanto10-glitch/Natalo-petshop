import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/screens/feed_user_search_screen.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';
import 'package:natalo_petshop_flutter/services/follow_service.dart';

Future<void> pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('hashtag-mode: typing #something shows hashtag results',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedUserSearchScreen(
        searchHashtagsOverride: (q) async => [
          const HashtagSuggestion(name: 'kucing', postCount: 12),
          const HashtagSuggestion(name: 'kucinglucu', postCount: 4),
        ],
      ),
    ));
    await pumpBounded(tester);

    await tester.enterText(find.byType(TextField), '#kucing');
    await pumpBounded(tester);

    expect(find.text('12 postingan'), findsOneWidget);
    expect(find.text('#kucinglucu'), findsOneWidget);
    expect(find.text('4 postingan'), findsOneWidget);
  });

  testWidgets('tapping a hashtag result pushes /hashtag with plain name',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: FeedUserSearchScreen(
        searchHashtagsOverride: (q) async => [
          const HashtagSuggestion(name: 'kucing', postCount: 12),
        ],
      ),
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => const Scaffold(body: SizedBox()),
      ),
    ));
    await pumpBounded(tester);

    await tester.enterText(find.byType(TextField), '#kucing');
    await pumpBounded(tester);

    await tester.tap(find.text('12 postingan'));
    await pumpBounded(tester);

    expect(observer.pushedNames, contains('/hashtag'));
    expect(observer.pushedArguments['/hashtag'], 'kucing');
  });

  testWidgets('bare # with nothing after shows hashtag empty state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedUserSearchScreen(
        searchHashtagsOverride: (q) async =>
            throw StateError('should not be called for bare #'),
        searchUsersOverride: (q, {int limit = 20}) async =>
            throw StateError('should not call user search in hashtag mode'),
      ),
    ));
    await pumpBounded(tester);

    await tester.enterText(find.byType(TextField), '#');
    await pumpBounded(tester);

    expect(find.text('Akun yang mungkin kamu kenal'), findsNothing);
    expect(find.text('Pencarian gagal'), findsNothing);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<String> pushedNames = [];
  final Map<String, Object?> pushedArguments = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) {
      pushedNames.add(name);
      pushedArguments[name] = route.settings.arguments;
    }
    super.didPush(route, previousRoute);
  }
}
