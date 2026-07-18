import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';

void main() {
  testWidgets('menampilkan pesan + tombol Coba lagi tanpa pull-to-refresh',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentErrorRetryView(
            message: 'Gagal memuat komentar.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Gagal memuat komentar.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Coba lagi'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Coba lagi'));
    await tester.pump();
    expect(retries, 1);
  });
}
