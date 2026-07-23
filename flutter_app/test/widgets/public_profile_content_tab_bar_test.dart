import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/theme/natalo_colors.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_content_tab_bar.dart';

void main() {
  testWidgets('expanded public tabs are icon-only and neutral', (tester) async {
    await tester.pumpWidget(
      tabHarness(
        labelOpacity: 0,
        pillOpacity: 0,
        underlineOpacity: 1,
      ),
    );

    expect(find.text('Postingan'), findsNothing);
    expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
    expect(
      find.byKey(const Key('public_tab_sliding_underline')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    _expectNeutralForegrounds(tester);
  });

  testWidgets('collapsed tabs render three individual neutral pills', (
    tester,
  ) async {
    await tester.pumpWidget(
      tabHarness(
        labelOpacity: 1,
        pillOpacity: 1,
        underlineOpacity: 0,
      ),
    );

    expect(find.text('Postingan'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Ditandai'), findsOneWidget);
    expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_video_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_tagged_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_shared_surface')), findsNothing);
    expect(
      find.byKey(const Key('public_tab_sliding_underline')),
      findsNothing,
    );
    _expectNeutralForegrounds(tester);
  });

  testWidgets('collapsed tabs fit width 320 at text scale 2', (tester) async {
    await tester.pumpWidget(
      tabHarness(
        width: 320,
        textScaler: const TextScaler.linear(2),
        labelOpacity: 1,
        pillOpacity: 1,
        underlineOpacity: 0,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(PublicProfileContentTabBar)).left,
      0,
    );
    final label = tester.widget<Text>(find.text('Postingan'));
    expect(label.textScaler, const TextScaler.linear(1.3));
  });

  testWidgets(
    'full tab semantics remain buttons and selected outside visual scale cap',
    (tester) async {
      await tester.pumpWidget(
        tabHarness(
          width: 320,
          textScaler: const TextScaler.linear(2),
            labelOpacity: 1,
          pillOpacity: 1,
          underlineOpacity: 0,
        ),
      );

      for (final (label, selected) in <(String, bool)>[
        ('Postingan', true),
        ('Video', false),
        ('Ditandai', false),
      ]) {
        final semantics = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byTooltip(label),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(semantics.properties.label, label);
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.selected, selected);
      }

      for (final label in const ['Postingan', 'Video', 'Ditandai']) {
        expect(
          tester.widget<Text>(find.text(label)).textScaler,
          const TextScaler.linear(1.3),
        );
      }
    },
  );

  testWidgets('public tabs preserve tap and swipe controller semantics', (
    tester,
  ) async {
    var tappedIndex = -1;
    await tester.pumpWidget(
      tabHarness(
        labelOpacity: 1,
        pillOpacity: 1,
        underlineOpacity: 0,
        onTap: (index) => tappedIndex = index,
      ),
    );

    expect(
      tester.getSize(find.byType(PublicProfileContentTabBar)).height,
      PublicProfileContentTabBar.height,
    );

    await tester.tap(find.byKey(const Key('public_tab_video_pill')));
    await tester.pumpAndSettle();
    expect(tappedIndex, 1);
    expect(find.text('Video page'), findsOneWidget);

    await tester.drag(find.byType(TabBarView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ditandai page'), findsOneWidget);
  });

  testWidgets('tab bar draws no full-width Material divider', (tester) async {
    final controller = TabController(length: 3, vsync: const TestVSync());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PublicProfileContentTabBar(
          controller: controller,
          labelOpacity: 0,
          pillOpacity: 0,
          underlineOpacity: 1,
        ),
      ),
    ));
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.dividerColor, Colors.transparent);
    expect(tabBar.dividerHeight, 0);
  });

  testWidgets('active tab indicator slides between tabs (no snap)', (tester) async {
    final controller = TabController(length: 3, vsync: const TestVSync());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: PublicProfileContentTabBar(
            controller: controller,
            labelOpacity: 0,
            pillOpacity: 0,
            underlineOpacity: 1,
          ),
        ),
      ),
    ));
    await tester.pump();
    final underline = find.byKey(const Key('public_tab_sliding_underline'));
    expect(underline, findsOneWidget);
    final atTab0 = tester.getCenter(underline).dx;

    // Mulai transisi ke tab 1, pump SEBAGIAN (belum selesai).
    controller.animateTo(1);
    // Tick pertama animasi selalu elapsed=0 (baseline Ticker) — pump nol
    // durasi dulu untuk memulai animasi sebelum mengukur progres parsial.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.getCenter(underline).dx;

    // Indikator sudah bergeser dari tab 0, tapi belum sampai pusat tab 1.
    final tab1Center = 300 / 3 * 1.5; // slot width * (1 + 0.5)
    expect(midway, greaterThan(atTab0), reason: 'indikator harus bergeser, bukan snap');
    expect(midway, lessThan(tab1Center), reason: 'belum sampai tab 1 di tengah transisi');

    await tester.pump(const Duration(milliseconds: 400)); // selesaikan animasi
  });
}

void _expectNeutralForegrounds(WidgetTester tester) {
  for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
    expect(icon.color, isNot(NataloColors.primary));
  }
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.style?.color, isNot(NataloColors.primary));
  }
}

Widget tabHarness({
  double width = 400,
  TextScaler textScaler = TextScaler.noScaling,
  required double labelOpacity,
  required double pillOpacity,
  required double underlineOpacity,
  ValueChanged<int>? onTap,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 200,
          child: _PublicTabsHarness(
            labelOpacity: labelOpacity,
            pillOpacity: pillOpacity,
            underlineOpacity: underlineOpacity,
            onTap: onTap,
          ),
        ),
      ),
    ),
  );
}

class _PublicTabsHarness extends StatefulWidget {
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final ValueChanged<int>? onTap;

  const _PublicTabsHarness({
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    this.onTap,
  });

  @override
  State<_PublicTabsHarness> createState() => _PublicTabsHarnessState();
}

class _PublicTabsHarnessState extends State<_PublicTabsHarness>
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
    return Column(
      children: [
        PublicProfileContentTabBar(
          controller: _controller,
          labelOpacity: widget.labelOpacity,
          pillOpacity: widget.pillOpacity,
          underlineOpacity: widget.underlineOpacity,
          onTap: widget.onTap,
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: const [
              Center(child: Text('Postingan page')),
              Center(child: Text('Video page')),
              Center(child: Text('Ditandai page')),
            ],
          ),
        ),
      ],
    );
  }
}
