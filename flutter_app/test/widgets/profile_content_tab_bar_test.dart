import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/profile_content_tab_bar.dart';

void main() {
  testWidgets('profile tabs are large, tappable, and swipe between pages', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _ProfileTabsHarness()));

    expect(
      tester.getSize(find.byType(ProfileContentTabBar)).height,
      closeTo(ProfileContentTabBar.height, 0.01),
    );
    expect(find.byKey(const Key('profile_tab_posts')), findsOneWidget);
    expect(find.byKey(const Key('profile_tab_video')), findsOneWidget);
    expect(find.byKey(const Key('profile_tab_shop')), findsOneWidget);
    expect(find.text('Postingan page'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile_tab_video')));
    await tester.pumpAndSettle();
    expect(find.text('Video page'), findsOneWidget);

    await tester.drag(
      find.byType(TabBarView),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belanja page'), findsOneWidget);
  });

  testWidgets('profile tabs use a segment-width sliding indicator', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _ProfileTabsHarness()));

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.indicatorSize, TabBarIndicatorSize.tab);
    expect(tabBar.indicator, isA<UnderlineTabIndicator>());
  });
}

class _ProfileTabsHarness extends StatefulWidget {
  const _ProfileTabsHarness();

  @override
  State<_ProfileTabsHarness> createState() => _ProfileTabsHarnessState();
}

class _ProfileTabsHarnessState extends State<_ProfileTabsHarness>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ProfileContentTabBar(controller: _controller),
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: const [
                Center(child: Text('Postingan page')),
                Center(child: Text('Video page')),
                Center(child: Text('Belanja page')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
