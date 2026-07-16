import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';

void main() {
  testWidgets('official public renders mutuals, message, and no catalog CTA',
      (tester) async {
    var messageCount = 0;
    await tester.pumpWidget(headerHarness(
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        isOfficial: true,
        isFollowing: true,
        mutualFollowers: PublicProfileMutualSummary(
          items: [
            PublicProfileMutualFollower(id: 'user-1', name: 'Mona'),
            PublicProfileMutualFollower(id: 'user-2', name: 'Riko'),
          ],
          totalCount: 7,
        ),
      ),
      chatEnabled: true,
      onMessage: () => messageCount += 1,
    ));
    expect(find.text('Pesan'), findsOneWidget);
    expect(find.textContaining('Diikuti oleh'), findsOneWidget);
    expect(find.text('Lihat Etalase Produk'), findsNothing);
    await tester.tap(find.text('Pesan'));
    expect(messageCount, 1);
  });

  testWidgets('regular public has no message and no mutual row',
      (tester) async {
    await tester.pumpWidget(headerHarness(
      profile: const PublicProfile(
        id: 'user-1',
        name: 'Mona',
        username: 'mona',
      ),
      chatEnabled: true,
      width: 320,
    ));
    expect(find.text('Pesan'), findsNothing);
    expect(find.textContaining('Diikuti oleh'), findsNothing);
    expect(find.text('Ikuti'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('official owner gets edit and never follow or message',
      (tester) async {
    await tester.pumpWidget(headerHarness(
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        isOfficial: true,
        isOwner: true,
      ),
      chatEnabled: true,
      onEditProfile: () {},
    ));
    expect(find.text('Edit Profil'), findsOneWidget);
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Pesan'), findsNothing);
  });

  testWidgets('empty optional rows leave no replacement spacing',
      (tester) async {
    await tester.pumpWidget(headerHarness(
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        isOfficial: true,
      ),
      chatEnabled: false,
      width: 320,
      textScaler: const TextScaler.linear(2),
    ));
    expect(find.byKey(const Key('official_mutual_row')), findsNothing);
    expect(find.byKey(const Key('official_message_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing owner callback does not render a dead primary action',
      (tester) async {
    await tester.pumpWidget(headerHarness(
      profile: const PublicProfile(
        id: 'user-1',
        name: 'Mona',
        isOwner: true,
      ),
      width: 320,
    ));
    expect(find.text('Edit Profil'), findsNothing);
    expect(find.text('Ikuti'), findsNothing);
  });
}

Widget headerHarness({
  required PublicProfile profile,
  bool chatEnabled = false,
  VoidCallback? onMessage,
  VoidCallback? onEditProfile,
  double width = 393,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        padding: const EdgeInsets.only(top: 59, bottom: 34),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: PublicProfileExpandedHeader(
              profile: profile,
              followBusy: false,
              chatEnabled: chatEnabled,
              onFollowToggle: () {},
              onFollowersTap: () {},
              onFollowingTap: () {},
              onEditProfile: onEditProfile,
              onShareProfile: () {},
              onMessage: onMessage,
            ),
          ),
        ),
      ),
    ),
  );
}
